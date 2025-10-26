const std = @import("std");
const quic_zig = @import("quic_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse environment variables for interop runner
    const testcase = std.process.getEnvVarOwned(allocator, "TESTCASE") catch null;
    defer if (testcase) |tc| allocator.free(tc);

    const www_dir = std.process.getEnvVarOwned(allocator, "WWW") catch "/www";
    defer allocator.free(www_dir);

    const cert_path = std.process.getEnvVarOwned(allocator, "CERT") catch "/certs/cert.pem";
    defer allocator.free(cert_path);

    const key_path = std.process.getEnvVarOwned(allocator, "KEY") catch "/certs/priv.key";
    defer allocator.free(key_path);

    const qlogdir = std.process.getEnvVarOwned(allocator, "QLOGDIR") catch null;
    defer if (qlogdir) |dir| allocator.free(dir);

    const sslkeylogfile = std.process.getEnvVarOwned(allocator, "SSLKEYLOGFILE") catch null;
    defer if (sslkeylogfile) |file| allocator.free(file);

    std.debug.print("QUIC Server starting...\n", .{});
    std.debug.print("  Testcase: {s}\n", .{testcase orelse "none"});
    std.debug.print("  WWW directory: {s}\n", .{www_dir});
    std.debug.print("  Certificate: {s}\n", .{cert_path});
    std.debug.print("  Private key: {s}\n", .{key_path});
    if (qlogdir) |dir| {
        std.debug.print("  QLOG directory: {s}\n", .{dir});
    }
    if (sslkeylogfile) |file| {
        std.debug.print("  SSL Key Log: {s}\n", .{file});
    }

    // Check if testcase is supported
    if (testcase) |tc| {
        // List of unsupported test cases - exit with 127
        const unsupported_tests = [_][]const u8{
            // Add unsupported test cases here as you implement features
            // Example: "chacha20", "zerortt", etc.
        };

        for (unsupported_tests) |unsupported| {
            if (std.mem.eql(u8, tc, unsupported)) {
                std.debug.print("Unsupported testcase: {s}\n", .{tc});
                std.process.exit(127);
            }
        }
    }

    // TODO: Implement actual QUIC server
    // For now, this is a skeleton that demonstrates the structure
    std.debug.print("Server would listen on port 443...\n", .{});
    std.debug.print("Server would serve files from {s}...\n", .{www_dir});

    // Placeholder - replace with actual QUIC server implementation
    std.debug.print("Server setup complete (placeholder implementation)\n", .{});

    // Exit successfully
    std.process.exit(0);
}
