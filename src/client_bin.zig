const std = @import("std");
const quic_zig = @import("quic_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse environment variables for interop runner
    const testcase = std.process.getEnvVarOwned(allocator, "TESTCASE") catch null;
    defer if (testcase) |tc| allocator.free(tc);

    const requests = std.process.getEnvVarOwned(allocator, "REQUESTS") catch {
        std.debug.print("Error: REQUESTS environment variable not set\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(requests);

    const download_dir = std.process.getEnvVarOwned(allocator, "DOWNLOADS") catch "/downloads";
    defer allocator.free(download_dir);

    const qlogdir = std.process.getEnvVarOwned(allocator, "QLOGDIR") catch null;
    defer if (qlogdir) |dir| allocator.free(dir);

    const sslkeylogfile = std.process.getEnvVarOwned(allocator, "SSLKEYLOGFILE") catch null;
    defer if (sslkeylogfile) |file| allocator.free(file);

    std.debug.print("QUIC Client starting...\n", .{});
    std.debug.print("  Testcase: {s}\n", .{testcase orelse "none"});
    std.debug.print("  Requests: {s}\n", .{requests});
    std.debug.print("  Download directory: {s}\n", .{download_dir});
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
        };

        for (unsupported_tests) |unsupported| {
            if (std.mem.eql(u8, tc, unsupported)) {
                std.debug.print("Unsupported testcase: {s}\n", .{tc});
                std.process.exit(127);
            }
        }
    }

    // Parse URLs from REQUESTS (space-separated)
    std.debug.print("Parsing requests...\n", .{});
    var iter = std.mem.splitScalar(u8, requests, ' ');
    var url_count: usize = 0;
    while (iter.next()) |url| {
        if (url.len > 0) {
            std.debug.print("  - {s}\n", .{url});
            url_count += 1;
        }
    }

    std.debug.print("Found {d} URLs to download\n", .{url_count});

    // TODO: Implement actual QUIC client
    // For now, this is a skeleton that demonstrates the structure
    std.debug.print("Client would download files to {s}...\n", .{download_dir});
    std.debug.print("All downloads completed successfully (placeholder)\n", .{});

    // Exit successfully for testing
    std.process.exit(0);
}
