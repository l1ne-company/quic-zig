const std = @import("std");

/// List of supported test cases
/// See: https://github.com/quic-interop/quic-interop-runner
const SUPPORTED_TEST_CASES = [_][]const u8{
    "handshake",
    "transfer",
    "retry",
    "http3",
    "multiconnect",
    "zerortt",
    "resumption",
    "chacha20",
    "keyupdate",
    "v2",
};

fn isTestCaseSupported(testcase: []const u8) bool {
    for (SUPPORTED_TEST_CASES) |supported| {
        if (std.mem.eql(u8, testcase, supported)) {
            return true;
        }
    }
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup routing (call /setup.sh from the base image)
    {
        var setup = std.process.Child.init(&[_][]const u8{"/setup.sh"}, allocator);
        setup.stdout_behavior = .Inherit;
        setup.stderr_behavior = .Inherit;
        const setup_result = setup.spawnAndWait() catch |err| {
            std.debug.print("Failed to run /setup.sh: {}\n", .{err});
            std.process.exit(1);
        };
        if (setup_result != .Exited or setup_result.Exited != 0) {
            std.debug.print("/setup.sh failed\n", .{});
            std.process.exit(1);
        }
    }

    // Create necessary directories
    std.fs.cwd().makePath("downloads") catch {};
    std.fs.cwd().makePath("logs") catch {};

    // Get role from environment
    const role = std.process.getEnvVarOwned(allocator, "ROLE") catch "server";
    defer allocator.free(role);

    const testcase = std.process.getEnvVarOwned(allocator, "TESTCASE") catch null;
    defer if (testcase) |tc| allocator.free(tc);

    std.debug.print("QUIC-Zig Endpoint Starting\n", .{});
    std.debug.print("Role: {s}\n", .{role});
    std.debug.print("Testcase: {s}\n", .{testcase orelse "none"});

    // Check if test case is supported
    if (testcase) |tc| {
        const supported = isTestCaseSupported(tc);
        if (!supported) {
            std.debug.print("Test case '{s}' is not supported\n", .{tc});
            std.process.exit(127); // Exit with 127 for unsupported test cases
        }
    }

    if (std.mem.eql(u8, role, "client")) {
        // Client mode - wait for simulator
        std.debug.print("Waiting for simulator to start...\n", .{});

        // Call wait-for-it.sh
        var wait = std.process.Child.init(&[_][]const u8{
            "/wait-for-it.sh",
            "sim:57832",
            "-s",
            "-t",
            "30",
        }, allocator);
        wait.stdout_behavior = .Inherit;
        wait.stderr_behavior = .Inherit;
        _ = wait.spawnAndWait() catch |err| {
            std.debug.print("Failed to wait for simulator: {}\n", .{err});
        };

        std.debug.print("Starting QUIC client\n", .{});

        const requests = std.process.getEnvVarOwned(allocator, "REQUESTS") catch "";
        defer allocator.free(requests);
        std.debug.print("Requests: {s}\n", .{requests});

        // Execute client
        const argv = [_][]const u8{"/usr/local/bin/quic_client"};
        return std.process.execve(allocator, &argv, null);
    } else if (std.mem.eql(u8, role, "server")) {
        // Server mode
        std.debug.print("Starting QUIC server on port 443\n", .{});

        const www = std.process.getEnvVarOwned(allocator, "WWW") catch "/www";
        defer allocator.free(www);
        std.debug.print("Serving files from: {s}\n", .{www});

        // Execute server
        const argv = [_][]const u8{"/usr/local/bin/quic_server"};
        return std.process.execve(allocator, &argv, null);
    } else {
        std.debug.print("Unknown ROLE: {s}\n", .{role});
        std.process.exit(1);
    }
}
