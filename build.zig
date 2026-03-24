const std = @import("std");
const builtin = @import("builtin");

const zig_version = std.SemanticVersion{ .major = 0, .minor = 15, .patch = 1 };

comptime {
    const ok = zig_version.major == builtin.zig_version.major and
        zig_version.minor == builtin.zig_version.minor;
    if (!ok) @compileError(std.fmt.comptimePrint(
        "unsupported zig version: expected 0.15.x, found {any}",
        .{builtin.zig_version},
    ));
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // -----------------------------------------------------------------------
    // Library modules
    // -----------------------------------------------------------------------
    const utils_mod = b.addModule("quic-zig-utils", .{
        .root_source_file = b.path("src/utils/root.zig"),
        .target = target,
    });

    const core_mod = b.addModule("quic-zig-core", .{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
    });
    core_mod.addImport("utils", utils_mod);

    const client_mod = b.addModule("quic-zig-client", .{
        .root_source_file = b.path("src/client/root.zig"),
        .target = target,
    });
    client_mod.addImport("core", core_mod);

    const server_mod = b.addModule("quic-zig-server", .{
        .root_source_file = b.path("src/server/root.zig"),
        .target = target,
    });
    server_mod.addImport("core", core_mod);

    const crypto_mod = b.addModule("quic-zig-crypto", .{
        .root_source_file = b.path("src/crypto/root.zig"),
        .target = target,
    });

    // Root module — what consumers import as "quic-zig"
    const quic_mod = b.addModule("quic-zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    quic_mod.addImport("core", core_mod);
    quic_mod.addImport("client", client_mod);
    quic_mod.addImport("server", server_mod);
    quic_mod.addImport("crypto", crypto_mod);
    quic_mod.addImport("utils", utils_mod);

    // -----------------------------------------------------------------------
    // Tests  (zig build test  or  zig build test-<module>)
    // -----------------------------------------------------------------------
    const test_step = b.step("test", "Run all tests");
    const mods = [_]struct { name: []const u8, mod: *std.Build.Module }{
        .{ .name = "utils", .mod = utils_mod },
        .{ .name = "core", .mod = core_mod },
        .{ .name = "client", .mod = client_mod },
        .{ .name = "server", .mod = server_mod },
        .{ .name = "crypto", .mod = crypto_mod },
        .{ .name = "main", .mod = quic_mod },
    };
    for (mods) |m| {
        const t = b.addTest(.{ .root_module = m.mod });
        const run_t = b.addRunArtifact(t);
        const s = b.step(b.fmt("test-{s}", .{m.name}), b.fmt("Test {s}", .{m.name}));
        s.dependOn(&run_t.step);
        test_step.dependOn(&run_t.step);
    }
}
