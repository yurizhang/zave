const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true, // for std.c.getenv to read $HOME
    });

    // Native macOS window (WKWebView) — system frameworks only.
    mod.addCSourceFile(.{ .file = b.path("src/macwin.m"), .flags = &.{} });
    mod.linkFramework("Cocoa", .{});
    mod.linkFramework("WebKit", .{});

    const exe = b.addExecutable(.{
        .name = "filemanager",
        .root_module = mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the file manager server");
    run_step.dependOn(&run_cmd.step);
}
