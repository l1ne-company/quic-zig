const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const quic_dep = b.dependency("quic_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "quic_zig", .module = quic_dep.module("quic-zig") },
        },
    });
    const exe = b.addExecutable(.{ .name = "sniffer", .root_module = mod });

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the sniffer").dependOn(&run.step);
}
