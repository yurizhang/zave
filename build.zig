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
    // When cross-compiling (e.g. x86_64 on an arm64 host) Zig can't auto-find
    // the SDK, so point it at the frameworks/headers explicitly.
    if (b.option([]const u8, "macos-sdk", "Path to the macOS SDK (for cross builds)")) |sdk| {
        mod.addSystemFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{sdk}) });
        mod.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/usr/include", .{sdk}) });
        mod.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/usr/lib", .{sdk}) });
    }
    mod.linkFramework("Cocoa", .{});
    mod.linkFramework("WebKit", .{});

    const exe = b.addExecutable(.{
        .name = "zave",
        .root_module = mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Build and run Zave");
    run_step.dependOn(&run_cmd.step);
}
