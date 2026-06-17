const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const http = std.http;

const index_html = @embedFile("index.html");
const tabler_css = @embedFile("assets/tabler-icons.min.css");
const tabler_woff2 = @embedFile("assets/fonts/tabler-icons.woff2");

const port: u16 = 8080;

/// 读取 $HOME；读不到时退回 "/"。
fn homeDir() []const u8 {
    if (std.c.getenv("HOME")) |h| return std.mem.span(h);
    return "/";
}

const json_ct: []const http.Header = &.{.{ .name = "content-type", .value = "application/json; charset=utf-8" }};

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    var threaded: Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var addr = try net.IpAddress.parse("127.0.0.1", port);
    var server = try addr.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    std.debug.print("文件管理器已启动 → http://127.0.0.1:{d}\n", .{port});

    while (true) {
        const stream = server.accept(io) catch |err| {
            std.debug.print("accept 出错: {s}\n", .{@errorName(err)});
            continue;
        };
        handleConn(io, gpa, stream);
    }
}

fn handleConn(io: Io, gpa: std.mem.Allocator, stream: net.Stream) void {
    defer stream.close(io);

    var read_buf: [16 * 1024]u8 = undefined;
    var write_buf: [64 * 1024]u8 = undefined;
    var sr = stream.reader(io, &read_buf);
    var sw = stream.writer(io, &write_buf);
    var server = http.Server.init(&sr.interface, &sw.interface);

    while (true) {
        var req = server.receiveHead() catch return;
        route(io, gpa, &req) catch return;
        if (!req.head.keep_alive) return;
    }
}

const Op = enum { move, copy };

fn route(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request) !void {
    const target = req.head.target;

    if (std.mem.startsWith(u8, target, "/api/list")) return handleList(io, gpa, req, target);
    if (std.mem.startsWith(u8, target, "/api/move")) return handleTransfer(io, gpa, req, target, .move);
    if (std.mem.startsWith(u8, target, "/api/copy")) return handleTransfer(io, gpa, req, target, .copy);
    if (std.mem.startsWith(u8, target, "/api/delete")) return handleDelete(io, gpa, req, target);
    if (std.mem.startsWith(u8, target, "/api/mkdir")) return handleMkdir(io, gpa, req, target);

    if (std.mem.startsWith(u8, target, "/assets/fonts/tabler-icons.woff2")) {
        return req.respond(tabler_woff2, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "font/woff2" },
                .{ .name = "cache-control", .value = "max-age=86400" },
            },
        });
    }
    if (std.mem.startsWith(u8, target, "/assets/tabler-icons.min.css")) {
        return req.respond(tabler_css, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/css; charset=utf-8" },
                .{ .name = "cache-control", .value = "max-age=86400" },
            },
        });
    }

    try req.respond(index_html, .{
        .extra_headers = &.{.{ .name = "content-type", .value = "text/html; charset=utf-8" }},
    });
}

// ───────────────────────── 列目录 ─────────────────────────

fn handleList(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const raw_path = queryParam(target, "path") orelse "";
    const decoded = try percentDecode(arena, raw_path);
    const path = if (decoded.len == 0) homeDir() else decoded;

    const json = buildListing(io, arena, path) catch |err| blk: {
        var aw = std.Io.Writer.Allocating.init(arena);
        try aw.writer.print("{{\"error\":\"无法打开: {s} ({s})\"}}", .{ path, @errorName(err) });
        break :blk aw.written();
    };

    try req.respond(json, .{ .extra_headers = json_ct });
}

fn buildListing(io: Io, arena: std.mem.Allocator, path: []const u8) ![]u8 {
    var dir = try Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
    defer dir.close(io);

    var aw = std.Io.Writer.Allocating.init(arena);
    const w = &aw.writer;

    try w.writeAll("{\"path\":");
    try writeJsonString(w, path);
    try w.writeAll(",\"home\":");
    try writeJsonString(w, homeDir());
    try w.writeAll(",\"entries\":[");

    var it = dir.iterate();
    var first = true;
    while (try it.next(io)) |entry| {
        if (!first) try w.writeByte(',');
        first = false;

        const is_dir = entry.kind == .directory;
        const st: ?Io.Dir.Stat = dir.statFile(io, entry.name, .{}) catch null;
        const size: u64 = if (is_dir) 0 else if (st) |s| s.size else 0;
        const mtime_ms: i64 = if (st) |s| s.mtime.toMilliseconds() else 0;

        try w.writeAll("{\"name\":");
        try writeJsonString(w, entry.name);
        try w.print(",\"kind\":\"{s}\",\"size\":{d},\"mtime\":{d}}}", .{
            if (is_dir) "directory" else "file",
            size,
            mtime_ms,
        });
    }

    try w.writeAll("]}");
    return aw.written();
}

// ───────────────────────── 移动 / 复制 ─────────────────────────

fn handleTransfer(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8, op: Op) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const from = try percentDecode(arena, queryParam(target, "from") orelse "");
    const to = try percentDecode(arena, queryParam(target, "to") orelse "");

    doTransfer(io, arena, op, from, to) catch |err| return respondErr(req, arena, err);
    try respondOk(req);
}

fn doTransfer(io: Io, arena: std.mem.Allocator, op: Op, from: []const u8, to: []const u8) !void {
    if (from.len == 0 or to.len == 0) return error.MissingParam;
    if (!std.fs.path.isAbsolute(from) or !std.fs.path.isAbsolute(to)) return error.NotAbsolute;
    if (std.mem.eql(u8, from, to)) return error.SameLocation;

    switch (op) {
        .move => try Io.Dir.renameAbsolute(from, to, io),
        .copy => {
            // 防止把目录复制进它自己的子目录里（会无限递归）
            const from_slash = try std.fmt.allocPrint(arena, "{s}/", .{from});
            if (std.mem.startsWith(u8, to, from_slash)) return error.IntoItself;
            try copyPath(io, arena, from, to);
        },
    }
}

fn copyPath(io: Io, arena: std.mem.Allocator, src: []const u8, dst: []const u8) !void {
    const st = try Io.Dir.cwd().statFile(io, src, .{});
    if (st.kind == .directory) {
        try copyTree(io, arena, src, dst);
    } else {
        try Io.Dir.copyFileAbsolute(src, dst, io, .{});
    }
}

fn copyTree(io: Io, arena: std.mem.Allocator, src: []const u8, dst: []const u8) !void {
    try Io.Dir.createDirAbsolute(io, dst, .default_dir);

    var dir = try Io.Dir.openDirAbsolute(io, src, .{ .iterate = true });
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        const child_src = try std.fmt.allocPrint(arena, "{s}/{s}", .{ src, entry.name });
        const child_dst = try std.fmt.allocPrint(arena, "{s}/{s}", .{ dst, entry.name });
        if (entry.kind == .directory) {
            try copyTree(io, arena, child_src, child_dst);
        } else {
            try Io.Dir.copyFileAbsolute(child_src, child_dst, io, .{});
        }
    }
}

// ───────────────────────── 删除 ─────────────────────────

fn handleDelete(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const path = try percentDecode(arena, queryParam(target, "path") orelse "");

    doDelete(io, path) catch |err| return respondErr(req, arena, err);
    try respondOk(req);
}

fn doDelete(io: Io, path: []const u8) !void {
    if (path.len == 0) return error.MissingParam;
    if (!std.fs.path.isAbsolute(path)) return error.NotAbsolute;
    if (std.mem.eql(u8, path, "/")) return error.RefusingToDeleteRoot;

    const st = try Io.Dir.cwd().statFile(io, path, .{});
    if (st.kind == .directory) {
        try Io.Dir.cwd().deleteTree(io, path);
    } else {
        try Io.Dir.deleteFileAbsolute(io, path);
    }
}

// ───────────────────────── 新建文件夹 ─────────────────────────

fn handleMkdir(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const path = try percentDecode(arena, queryParam(target, "path") orelse "");

    doMkdir(io, path) catch |err| return respondErr(req, arena, err);
    try respondOk(req);
}

fn doMkdir(io: Io, path: []const u8) !void {
    if (path.len == 0) return error.MissingParam;
    if (!std.fs.path.isAbsolute(path)) return error.NotAbsolute;
    try Io.Dir.createDirAbsolute(io, path, .default_dir);
}

// ───────────────────────── 通用响应 ─────────────────────────

fn respondOk(req: *http.Server.Request) !void {
    // keep_alive=false：写操作是 POST，可能不带 Content-Length，
    // 关掉连接复用可避开 discardBody 对 body 边界的断言。
    try req.respond("{\"ok\":true}", .{ .extra_headers = json_ct, .keep_alive = false });
}

fn respondErr(req: *http.Server.Request, arena: std.mem.Allocator, err: anyerror) !void {
    var aw = std.Io.Writer.Allocating.init(arena);
    try aw.writer.print("{{\"error\":\"{s}\"}}", .{@errorName(err)});
    try req.respond(aw.written(), .{
        .status = .bad_request,
        .extra_headers = json_ct,
        .keep_alive = false,
    });
}

// ───────────────────────── 工具函数 ─────────────────────────

/// 从 "/api/list?path=%2Ffoo" 这样的 target 里取出某个查询参数（未解码）。
fn queryParam(target: []const u8, key: []const u8) ?[]const u8 {
    const q = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    var it = std.mem.splitScalar(u8, target[q + 1 ..], '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, pair[0..eq], key)) return pair[eq + 1 ..];
    }
    return null;
}

/// URL 百分号解码：%XX → 字节，'+' → 空格。
fn percentDecode(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = try alloc.alloc(u8, s.len);
    var i: usize = 0;
    var j: usize = 0;
    while (i < s.len) {
        if (s[i] == '%' and i + 2 < s.len) {
            const hi = std.fmt.charToDigit(s[i + 1], 16) catch {
                out[j] = s[i];
                i += 1;
                j += 1;
                continue;
            };
            const lo = std.fmt.charToDigit(s[i + 2], 16) catch {
                out[j] = s[i];
                i += 1;
                j += 1;
                continue;
            };
            out[j] = @as(u8, hi) * 16 + lo;
            i += 3;
            j += 1;
        } else if (s[i] == '+') {
            out[j] = ' ';
            i += 1;
            j += 1;
        } else {
            out[j] = s[i];
            i += 1;
            j += 1;
        }
    }
    return out[0..j];
}

/// 把字符串作为合法 JSON 字符串写出（带引号、转义）。
fn writeJsonString(w: *std.Io.Writer, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        else => if (c < 0x20) try w.print("\\u{x:0>4}", .{c}) else try w.writeByte(c),
    };
    try w.writeByte('"');
}
