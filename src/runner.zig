const std = @import("std");
const quic_zig = @import("quic_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse environment variables for interop runner
    const role = std.process.getEnvVarOwned(allocator, "ROLE") catch "runner";
    defer allocator.free(role);

    const testcase = std.process.getEnvVarOwned(allocator, "TESTCASE") catch null;
    defer if (testcase) |tc| allocator.free(tc);

    std.debug.print("QUIC Interop Runner starting...\n", .{});
    std.debug.print("  Role: {s}\n", .{role});
    std.debug.print("  Testcase: {s}\n", .{testcase orelse "all"});

    // Determine which mode to run based on ROLE environment variable
    if (std.mem.eql(u8, role, "server")) {
        std.debug.print("Running in SERVER mode\n", .{});
        // Delegate to server implementation
        const server_path = try std.fs.selfExeDirPathAlloc(allocator);
        defer allocator.free(server_path);

        const argv = [_][]const u8{"quic_server"};
        return std.process.execve(allocator, &argv, null);
    } else if (std.mem.eql(u8, role, "client")) {
        std.debug.print("Running in CLIENT mode\n", .{});
        // Delegate to client implementation
        const client_path = try std.fs.selfExeDirPathAlloc(allocator);
        defer allocator.free(client_path);

        const argv = [_][]const u8{"quic_client"};
        return std.process.execve(allocator, &argv, null);
    } else {
        // Run as test coordinator - orchestrate local tests
        std.debug.print("\n=== Running QUIC Interop Tests ===\n\n", .{});

        const test_cases = [_][]const u8{
            "handshake",
            "transfer",
            "retry",
            "resumption",
            "zerortt",
            "multiconnect",
        };

        // Determine which tests to run
        const tests_to_run = if (testcase) |tc| &[_][]const u8{tc} else &test_cases;

        var passed: usize = 0;
        var failed: usize = 0;
        var skipped: usize = 0;

        for (tests_to_run) |test_name| {
            std.debug.print("Running test: {s}\n", .{test_name});
            std.debug.print("  Starting server...\n", .{});

            // Get path to executables
            const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
            defer allocator.free(exe_dir);

            const server_path = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "quic_server" });
            defer allocator.free(server_path);

            const client_path = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "quic_client" });
            defer allocator.free(client_path);

            // Start server in background
            var server = std.process.Child.init(&[_][]const u8{server_path}, allocator);
            var env_map = try std.process.getEnvMap(allocator);
            defer env_map.deinit();

            try env_map.put("ROLE", "server");
            try env_map.put("TESTCASE", test_name);
            try env_map.put("WWW", "test-data/www");
            try env_map.put("CERT", "test-data/certs/cert.pem");
            try env_map.put("KEY", "test-data/certs/priv.key");

            server.env_map = &env_map;
            server.stdout_behavior = .Ignore;
            server.stderr_behavior = .Ignore;

            server.spawn() catch |err| {
                std.debug.print("  ✗ Failed to start server: {}\n", .{err});
                skipped += 1;
                continue;
            };

            // Give server time to start (100ms)
            std.Thread.sleep(100 * std.time.ns_per_ms);

            std.debug.print("  Starting client...\n", .{});

            // Run client
            var client = std.process.Child.init(&[_][]const u8{client_path}, allocator);
            var client_env_map = try std.process.getEnvMap(allocator);
            defer client_env_map.deinit();

            try client_env_map.put("ROLE", "client");
            try client_env_map.put("TESTCASE", test_name);
            try client_env_map.put("REQUESTS", "https://localhost:443/index.html https://localhost:443/test.txt");
            try client_env_map.put("DOWNLOADS", "test-data/downloads");

            client.env_map = &client_env_map;
            client.stdout_behavior = .Ignore;
            client.stderr_behavior = .Ignore;

            const client_result = client.spawnAndWait() catch |err| {
                std.debug.print("  ✗ Client failed: {}\n", .{err});
                _ = server.kill() catch {};
                failed += 1;
                continue;
            };

            // Kill server
            _ = server.kill() catch {};

            // Check result
            if (client_result == .Exited) {
                if (client_result.Exited == 0) {
                    std.debug.print("  ✓ Test passed\n\n", .{});
                    passed += 1;
                } else if (client_result.Exited == 127) {
                    std.debug.print("  ⊘ Test skipped (unsupported)\n\n", .{});
                    skipped += 1;
                } else {
                    std.debug.print("  ✗ Test failed (exit code {})\n\n", .{client_result.Exited});
                    failed += 1;
                }
            } else {
                std.debug.print("  ✗ Test failed (terminated)\n\n", .{});
                failed += 1;
            }
        }

        std.debug.print("=== Test Results ===\n", .{});
        std.debug.print("Passed:  {d}\n", .{passed});
        std.debug.print("Failed:  {d}\n", .{failed});
        std.debug.print("Skipped: {d}\n", .{skipped});
        std.debug.print("Total:   {d}\n", .{tests_to_run.len});

        if (failed > 0) {
            std.process.exit(1);
        }
    }

    std.process.exit(0);
}
