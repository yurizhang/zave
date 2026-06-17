const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const http = std.http;

const index_html = @embedFile("index.html");

const port: u16 = 8080;

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

fn route(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request) !void {
    const target = req.head.target;

    if (std.mem.startsWith(u8, target, "/api/list")) {
        try handleList(io, gpa, req, target);
        return;
    }

    try req.respond(index_html, .{
        .extra_headers = &.{.{ .name = "content-type", .value = "text/html; charset=utf-8" }},
    });
}

fn handleList(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8) !void {
    // 每个请求用一个 arena，结束统一释放，省心。
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const raw_path = queryParam(target, "path") orelse "";
    const decoded = try percentDecode(arena, raw_path);
    const path = if (decoded.len == 0) "/" else decoded;

    const json = buildListing(io, arena, path) catch |err| blk: {
        var aw = std.Io.Writer.Allocating.init(arena);
        try aw.writer.print("{{\"error\":\"无法打开: {s} ({s})\"}}", .{ path, @errorName(err) });
        break :blk aw.written();
    };

    try req.respond(json, .{
        .extra_headers = &.{.{ .name = "content-type", .value = "application/json; charset=utf-8" }},
    });
}

fn buildListing(io: Io, arena: std.mem.Allocator, path: []const u8) ![]u8 {
    var dir = try Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
    defer dir.close(io);

    var aw = std.Io.Writer.Allocating.init(arena);
    const w = &aw.writer;

    try w.writeAll("{\"path\":");
    try writeJsonString(w, path);
    try w.writeAll(",\"entries\":[");

    var it = dir.iterate();
    var first = true;
    while (try it.next(io)) |entry| {
        if (!first) try w.writeByte(',');
        first = false;

        const is_dir = entry.kind == .directory;
        const size: u64 = if (is_dir) 0 else blk: {
            const st = dir.statFile(io, entry.name, .{}) catch break :blk 0;
            break :blk st.size;
        };

        try w.writeAll("{\"name\":");
        try writeJsonString(w, entry.name);
        try w.print(",\"kind\":\"{s}\",\"size\":{d}}}", .{
            if (is_dir) "directory" else "file",
            size,
        });
    }

    try w.writeAll("]}");
    return aw.written();
}

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
