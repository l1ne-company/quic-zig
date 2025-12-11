const std = @import("std");
const builtin = @import("builtin");

const zig_version = std.SemanticVersion{
    .major = 0,
    .minor = 15,
    .patch = 1,
};

// use zig 0.15.x (allow patch version differences)
comptime {
    const zig_version_compatible = zig_version.major == builtin.zig_version.major and
        zig_version.minor == builtin.zig_version.minor;
    if (!zig_version_compatible) {
        @compileError(std.fmt.comptimePrint(
            "unsupported zig version: expected 0.15.x, found {any}",
            .{builtin.zig_version},
        ));
    }
}

const Modules = struct {
    core: *std.Build.Module,
    client: *std.Build.Module,
    server: *std.Build.Module,
    crypto: *std.Build.Module,
    utils: *std.Build.Module,
    main: *std.Build.Module,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create and setup all modules
    const modules = createModules(b, target);
    setupModuleDependencies(modules);

    // Build module install steps
    buildModuleSteps(b);

    // Build executables
    const exe = buildMainExecutable(b, target, optimize, modules.main);
    const server_exe = buildExecutable(b, "quic_server", "src/server_bin.zig", target, optimize, modules.main);
    const client_exe = buildExecutable(b, "quic_client", "src/client_bin.zig", target, optimize, modules.main);
    _ = buildExecutable(b, "quic_runner", "src/runner.zig", target, optimize, modules.main);
    _ = buildExecutable(b, "quic_endpoint", "src/endpoint.zig", target, optimize, null);

    // Build tests
    buildTests(b, modules.main, exe.root_module);

    // Build run steps
    buildRunSteps(b, exe, server_exe, client_exe);
}

/// Create all project modules
fn createModules(b: *std.Build, target: std.Build.ResolvedTarget) Modules {
    const core_module = b.addModule("quic-zig-core", .{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
    });

    const client_module = b.addModule("quic-zig-client", .{
        .root_source_file = b.path("src/client/root.zig"),
        .target = target,
    });

    const server_module = b.addModule("quic-zig-server", .{
        .root_source_file = b.path("src/server/root.zig"),
        .target = target,
    });

    const crypto_module = b.addModule("quic-zig-crypto", .{
        .root_source_file = b.path("src/crypto/root.zig"),
        .target = target,
    });

    const utils_module = b.addModule("quic-zig-utils", .{
        .root_source_file = b.path("src/utils/root.zig"),
        .target = target,
    });

    const main_module = b.addModule("quic-zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    return .{
        .core = core_module,
        .client = client_module,
        .server = server_module,
        .crypto = crypto_module,
        .utils = utils_module,
        .main = main_module,
    };
}

/// Setup dependencies between modules
fn setupModuleDependencies(modules: Modules) void {
    // Client and server depend on core
    modules.client.addImport("core", modules.core);
    modules.server.addImport("core", modules.core);

    // Main module imports all sub-modules
    modules.main.addImport("core", modules.core);
    modules.main.addImport("client", modules.client);
    modules.main.addImport("server", modules.server);
    modules.main.addImport("crypto", modules.crypto);
    modules.main.addImport("utils", modules.utils);
}

/// Create build steps for individual modules
fn buildModuleSteps(b: *std.Build) void {
    const modules_info: []const struct { name: []const u8, module_name: []const u8 } = &.{
        .{ .name = "quic-zig-core", .module_name = "Core QUIC protocol module" },
        .{ .name = "quic-zig-client", .module_name = "Client module" },
        .{ .name = "quic-zig-server", .module_name = "Server module" },
        .{ .name = "quic-zig-crypto", .module_name = "Crypto module" },
        .{ .name = "quic-zig-utils", .module_name = "Utils module" },
        .{ .name = "quic-zig", .module_name = "Main module" },
    };

    for (modules_info) |mod_info| {
        const step = b.step(mod_info.name, mod_info.module_name);
        step.dependOn(b.getInstallStep());
    }
}

/// Build a generic executable with optional module import
fn buildExecutable(
    b: *std.Build,
    name: []const u8,
    source_file: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    module: ?*std.Build.Module,
) *std.Build.Step.Compile {
    var root_module = b.createModule(.{
        .root_source_file = b.path(source_file),
        .target = target,
        .optimize = optimize,
    });

    if (module) |mod| {
        root_module.addImport("quic_zig", mod);
    }

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = root_module,
    });

    b.installArtifact(exe);
    return exe;
}

/// Build the main application executable
fn buildMainExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    module: *std.Build.Module,
) *std.Build.Step.Compile {
    return buildExecutable(b, "quic_zig", "src/main.zig", target, optimize, module);
}

/// Build and register all tests
fn buildTests(
    b: *std.Build,
    main_module: *std.Build.Module,
    exe_module: *std.Build.Module,
) void {
    const mod_tests = b.addTest(.{
        .root_module = main_module,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

/// Build and register run steps for main executables
fn buildRunSteps(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    server_exe: *std.Build.Step.Compile,
    client_exe: *std.Build.Step.Compile,
) void {
    // Main run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Server run step
    const server_step = b.step("server", "Run QUIC server on port 443");
    const server_run = b.addRunArtifact(server_exe);
    server_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        server_run.addArgs(args);
    }
    server_step.dependOn(&server_run.step);

    // Client run step
    const client_step = b.step("client", "Run QUIC client");
    const client_run = b.addRunArtifact(client_exe);
    client_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        client_run.addArgs(args);
    }
    client_step.dependOn(&client_run.step);

    // Runner hint step
    const runner_step = b.step("runner", "Run QUIC interop tests (use: test-interop)");
    const runner_hint = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        "echo 'Hint: Use test-interop command from nix develop shell for full interop testing' && echo 'This runs: zig build -Doptimize=ReleaseFast && docker build && uv run python run.py'",
    });
    runner_step.dependOn(&runner_hint.step);
}
