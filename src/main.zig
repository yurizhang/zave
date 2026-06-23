const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const http = std.http;

/// Native macOS window hosting a WKWebView (implemented in src/macwin.m).
extern fn openWebview(url: [*:0]const u8, title: [*:0]const u8, child_pid: c_int) void;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

const index_html = @embedFile("index.html");
const tabler_css = @embedFile("assets/tabler-icons.min.css");
const tabler_woff2 = @embedFile("assets/fonts/tabler-icons.woff2");

/// Default port (uncommon, so unlikely to clash); overridable via PORT or the UI.
const default_port: u16 = 9781;

/// Max bytes served by /api/file (cap so a huge file can't exhaust memory).
const max_file = 16 * 1024 * 1024;

/// Read $HOME; fall back to "/" if unset.
fn homeDir() []const u8 {
    if (std.c.getenv("HOME")) |h| return std.mem.span(h);
    return "/";
}

/// The current process environment, so it is preserved across `process.replace`
/// (used by the restart-on-port-change flow). Without this, the Threaded I/O
/// instance defaults to an empty environment and the re-exec'd process would
/// lose $HOME etc.
fn currentEnviron() std.process.Environ {
    const env = std.c.environ;
    var n: usize = 0;
    while (env[n] != null) : (n += 1) {}
    const slice: [:null]const ?[*:0]const u8 = @ptrCast(env[0..n :null]);
    return .{ .block = .{ .slice = slice } };
}

/// Absolute path of the persisted port config file (`$HOME/.window-finder-port`).
fn configPath(buf: []u8) ?[]const u8 {
    return std.fmt.bufPrint(buf, "{s}/.window-finder-port", .{homeDir()}) catch null;
}

/// Port saved by the user via /api/config, if any.
fn readConfigPort(io: Io) ?u16 {
    var pbuf: [1024]u8 = undefined;
    const path = configPath(&pbuf) orelse return null;
    var dbuf: [16]u8 = undefined;
    const data = Io.Dir.cwd().readFile(io, path, &dbuf) catch return null;
    const n = std.fmt.parseInt(u16, std.mem.trim(u8, data, " \r\n\t"), 10) catch return null;
    return if (n != 0) n else null;
}

/// Starting port: $PORT > saved config > `default_port`.
fn resolvePort(io: Io) u16 {
    if (std.c.getenv("PORT")) |p| {
        if (std.fmt.parseInt(u16, std.mem.span(p), 10)) |n| {
            if (n != 0) return n;
        } else |_| {}
    }
    return readConfigPort(io) orelse default_port;
}

const json_ct: []const http.Header = &.{.{ .name = "content-type", .value = "application/json; charset=utf-8" }};

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // Decide mode before creating the Io instance: with HEADLESS set we are the
    // server child; otherwise we are the window host and must make sure the
    // child we spawn inherits HEADLESS.
    const headless = std.c.getenv("HEADLESS") != null;
    if (!headless) _ = setenv("HEADLESS", "1", 1);

    var threaded: Io.Threaded = .init(gpa, .{ .environ = currentEnviron() });
    defer threaded.deinit();
    const io = threaded.io();

    if (headless) return runServer(io, gpa);
    try runHost(io, gpa);
}

/// Server process: bind a port and serve forever on the main thread.
/// (Cocoa-free, so the Threaded I/O behaves normally.)
fn runServer(io: Io, gpa: std.mem.Allocator) void {
    const want = resolvePort(io);
    var port: u16 = want;
    var server = while (port < want +| 20) : (port += 1) {
        var addr = net.IpAddress.parse("127.0.0.1", port) catch unreachable;
        if (addr.listen(io, .{})) |s| {
            break s;
        } else |err| switch (err) {
            error.AddressInUse => continue,
            else => {
                std.debug.print("listen error: {s}\n", .{@errorName(err)});
                return;
            },
        }
    } else {
        std.debug.print("No free port found from {d}–{d}.\n", .{ want, want +| 19 });
        return;
    };
    defer server.deinit(io);

    // The host parses this line to learn the chosen port.
    std.debug.print("File manager started → http://127.0.0.1:{d}\n", .{port});

    // Handle each connection concurrently so multiple windows (multiple
    // clients) don't block one another. Safe here: this process is headless
    // (no Cocoa run loop to conflict with the Threaded I/O).
    while (true) {
        const stream = server.accept(io) catch continue;
        _ = io.concurrent(handleConn, .{ io, gpa, stream }) catch {
            handleConn(io, gpa, stream); // fallback: handle inline
        };
    }
}

/// Host process: spawn the server child, learn its port from the child's
/// stdout, then open the native window pointing at it.
fn runHost(io: Io, gpa: std.mem.Allocator) !void {
    _ = gpa;
    var exe_buf: [4096]u8 = undefined;
    const exe_len = try std.process.executablePath(io, &exe_buf);
    const exe = exe_buf[0..exe_len];

    // The child logs its "started → …:PORT" line on stderr (std.debug.print),
    // so pipe stderr and read one line from it.
    const child = try std.process.spawn(io, .{ .argv = &.{exe}, .stderr = .pipe });
    const out = child.stderr orelse return error.NoChildStderr;

    var rbuf: [512]u8 = undefined;
    var reader = out.reader(io, &rbuf);
    const line = reader.interface.takeDelimiterExclusive('\n') catch "";
    const port = parsePort(line) orelse default_port;

    var url_buf: [64]u8 = undefined;
    const url = std.fmt.bufPrintZ(&url_buf, "http://127.0.0.1:{d}/", .{port}) catch unreachable;
    std.debug.print("window-finder → {s}\n", .{url});

    openWebview(url.ptr, "window-finder", @intCast(child.id orelse 0));
}

/// Extract the port from "…127.0.0.1:<port>…".
fn parsePort(s: []const u8) ?u16 {
    const marker = "127.0.0.1:";
    const at = std.mem.indexOf(u8, s, marker) orelse return null;
    const i = at + marker.len;
    var end = i;
    while (end < s.len and s[end] >= '0' and s[end] <= '9') : (end += 1) {}
    if (end == i) return null;
    return std.fmt.parseInt(u16, s[i..end], 10) catch null;
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
    if (std.mem.startsWith(u8, target, "/api/file")) return handleFile(io, gpa, req, target);
    if (std.mem.startsWith(u8, target, "/api/open")) return handleOpen(io, gpa, req, target);
    if (std.mem.startsWith(u8, target, "/api/terminal")) return handleTerminal(io, gpa, req, target);
    if (std.mem.startsWith(u8, target, "/api/config")) return handleConfig(io, gpa, req, target);
    if (std.mem.startsWith(u8, target, "/api/restart")) return handleRestart(io, req);
    if (std.mem.startsWith(u8, target, "/api/zip")) return handleZip(io, gpa, req, target);
    if (std.mem.startsWith(u8, target, "/api/unzip")) return handleUnzip(io, gpa, req, target);

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

// ───────────────────────── list directory ─────────────────────────

fn handleList(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const raw_path = queryParam(target, "path") orelse "";
    const decoded = try percentDecode(arena, raw_path);
    const path = if (decoded.len == 0) homeDir() else decoded;

    const json = buildListing(io, arena, path) catch |err| blk: {
        var aw = std.Io.Writer.Allocating.init(arena);
        try aw.writer.print("{{\"error\":\"Cannot open {s} ({s})\"}}", .{ path, @errorName(err) });
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

// ───────────────────────── move / copy ─────────────────────────

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
            // prevent copying a directory into its own subtree (infinite recursion)
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

// ───────────────────────── delete ─────────────────────────

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

// ───────────────────────── make directory ─────────────────────────

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

// ───────────────────────── raw file (preview) ─────────────────────────

fn handleFile(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const path = try percentDecode(arena, queryParam(target, "path") orelse "");
    serveFile(io, arena, req, path) catch |err| return respondErr(req, arena, err);
}

fn serveFile(io: Io, arena: std.mem.Allocator, req: *http.Server.Request, path: []const u8) !void {
    if (path.len == 0) return error.MissingParam;
    if (!std.fs.path.isAbsolute(path)) return error.NotAbsolute;

    const st = try Io.Dir.cwd().statFile(io, path, .{});
    if (st.kind == .directory) return error.IsDir;

    const cap: usize = @intCast(@min(st.size, max_file));
    const buf = try arena.alloc(u8, cap);
    const data = try Io.Dir.cwd().readFile(io, path, buf);

    try req.respond(data, .{
        .extra_headers = &.{.{ .name = "content-type", .value = contentType(path) }},
    });
}

/// Guess a Content-Type from the file extension (enough for browser preview).
fn contentType(path: []const u8) []const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse return "application/octet-stream";
    const e = path[dot + 1 ..];
    const eql = std.ascii.eqlIgnoreCase;
    if (eql(e, "png")) return "image/png";
    if (eql(e, "jpg") or eql(e, "jpeg")) return "image/jpeg";
    if (eql(e, "gif")) return "image/gif";
    if (eql(e, "webp")) return "image/webp";
    if (eql(e, "svg")) return "image/svg+xml";
    if (eql(e, "bmp")) return "image/bmp";
    if (eql(e, "ico")) return "image/x-icon";
    if (eql(e, "pdf")) return "application/pdf";
    // everything else previewable is treated as UTF-8 text
    return "text/plain; charset=utf-8";
}

// ───────────────────────── open with default app ─────────────────────────

fn handleOpen(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const path = try percentDecode(arena, queryParam(target, "path") orelse "");
    doOpen(io, path) catch |err| return respondErr(req, arena, err);
    try respondOk(req);
}

fn doOpen(io: Io, path: []const u8) !void {
    if (path.len == 0) return error.MissingParam;
    if (!std.fs.path.isAbsolute(path)) return error.NotAbsolute;

    var child = try std.process.spawn(io, .{ .argv = &.{ "/usr/bin/open", path } });
    _ = try child.wait(io);
}

fn handleTerminal(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const path = try percentDecode(arena, queryParam(target, "path") orelse "");
    doTerminal(io, path) catch |err| return respondErr(req, arena, err);
    try respondOk(req);
}

fn doTerminal(io: Io, path: []const u8) !void {
    if (path.len == 0) return error.MissingParam;
    if (!std.fs.path.isAbsolute(path)) return error.NotAbsolute;

    var child = try std.process.spawn(io, .{ .argv = &.{ "/usr/bin/open", "-a", "Terminal", path } });
    _ = try child.wait(io);
}

// ───────────────────────── compress / extract (zip) ─────────────────────────

fn handleZip(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const path = try percentDecode(arena, queryParam(target, "path") orelse "");
    doZip(io, arena, path) catch |err| return respondErr(req, arena, err);
    try respondOk(req);
}

fn doZip(io: Io, arena: std.mem.Allocator, path: []const u8) !void {
    if (path.len == 0) return error.MissingParam;
    if (!std.fs.path.isAbsolute(path)) return error.NotAbsolute;

    const parent = std.fs.path.dirname(path) orelse return error.NoParent;
    const name = std.fs.path.basename(path);
    // <path>.zip, made unique if it already exists
    const archive = try uniquePath(io, arena, try std.fmt.allocPrint(arena, "{s}.zip", .{path}));
    const archive_name = std.fs.path.basename(archive);

    // run inside the parent dir so stored paths are relative (clean archive)
    var child = try std.process.spawn(io, .{
        .argv = &.{ "/usr/bin/zip", "-r", "-q", archive_name, name },
        .cwd = .{ .path = parent },
    });
    const term = try child.wait(io);
    if (term != .exited or term.exited != 0) return error.ZipFailed;
}

fn handleUnzip(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const path = try percentDecode(arena, queryParam(target, "path") orelse "");
    doUnzip(io, arena, path) catch |err| return respondErr(req, arena, err);
    try respondOk(req);
}

fn doUnzip(io: Io, arena: std.mem.Allocator, path: []const u8) !void {
    if (path.len == 0) return error.MissingParam;
    if (!std.fs.path.isAbsolute(path)) return error.NotAbsolute;

    const parent = std.fs.path.dirname(path) orelse return error.NoParent;
    const stem = std.fs.path.stem(std.fs.path.basename(path));
    // extract into <parent>/<stem>/, made unique if it already exists
    const dest = try uniquePath(io, arena, try std.fmt.allocPrint(arena, "{s}/{s}", .{ parent, stem }));

    var child = try std.process.spawn(io, .{
        .argv = &.{ "/usr/bin/unzip", "-q", path, "-d", dest },
    });
    const term = try child.wait(io);
    if (term != .exited or term.exited != 0) return error.UnzipFailed;
}

/// Returns `base` if it does not exist, otherwise inserts " N" before the
/// extension until a free name is found.
fn uniquePath(io: Io, arena: std.mem.Allocator, base: []const u8) ![]const u8 {
    if (!pathExists(io, base)) return base;
    const ext = std.fs.path.extension(base);
    const stem = base[0 .. base.len - ext.len];
    var i: u32 = 2;
    while (i < 1000) : (i += 1) {
        const cand = try std.fmt.allocPrint(arena, "{s} {d}{s}", .{ stem, i, ext });
        if (!pathExists(io, cand)) return cand;
    }
    return error.TooManyCollisions;
}

fn pathExists(io: Io, path: []const u8) bool {
    _ = Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

// ───────────────────────── settings (persisted port) ─────────────────────────

fn handleConfig(io: Io, gpa: std.mem.Allocator, req: *http.Server.Request, target: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    if (req.head.method == .POST) {
        const raw = queryParam(target, "port") orelse "";
        const decoded = try percentDecode(arena, raw);
        const n = std.fmt.parseInt(u16, std.mem.trim(u8, decoded, " \r\n\t"), 10) catch
            return respondErr(req, arena, error.InvalidPort);
        if (n == 0) return respondErr(req, arena, error.InvalidPort);
        writeConfigPort(io, n) catch |err| return respondErr(req, arena, err);
        try respondOk(req);
    } else {
        const cfg = readConfigPort(io);
        var aw = std.Io.Writer.Allocating.init(arena);
        if (cfg) |n| {
            try aw.writer.print("{{\"configured\":{d},\"default\":{d}}}", .{ n, default_port });
        } else {
            try aw.writer.print("{{\"configured\":null,\"default\":{d}}}", .{default_port});
        }
        try req.respond(aw.written(), .{ .extra_headers = json_ct });
    }
}

/// Respond OK, then replace this process with a fresh copy (re-reads the
/// saved port and rebinds). On success `replace` never returns.
fn handleRestart(io: Io, req: *http.Server.Request) !void {
    try respondOk(req);
    try req.server.out.flush(); // make sure the client got the reply before we exec

    var buf: [4096]u8 = undefined;
    const n = std.process.executablePath(io, &buf) catch return;
    const path = buf[0..n];
    const err = std.process.replace(io, .{ .argv = &.{path} });
    std.debug.print("restart failed: {s}\n", .{@errorName(err)});
}

fn writeConfigPort(io: Io, n: u16) !void {
    var pbuf: [1024]u8 = undefined;
    const path = configPath(&pbuf) orelse return error.NoHome;
    var nbuf: [8]u8 = undefined;
    const data = try std.fmt.bufPrint(&nbuf, "{d}", .{n});
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

// ───────────────────────── shared responses ─────────────────────────

fn respondOk(req: *http.Server.Request) !void {
    // keep_alive=false: write ops are POSTs that may carry no Content-Length;
    // disabling connection reuse avoids discardBody asserting on body length.
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

// ───────────────────────── utilities ─────────────────────────

/// Extract a (still URL-encoded) query parameter from a target like "/api/list?path=%2Ffoo".
fn queryParam(target: []const u8, key: []const u8) ?[]const u8 {
    const q = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    var it = std.mem.splitScalar(u8, target[q + 1 ..], '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, pair[0..eq], key)) return pair[eq + 1 ..];
    }
    return null;
}

/// URL percent-decoding: %XX → byte, '+' → space.
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

/// Write a string as a valid JSON string (quoted and escaped).
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
