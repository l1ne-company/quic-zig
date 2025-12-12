//! QUIC-Zig - Modular QUIC Protocol Implementation
//!
//! This is the main entry point that re-exports all modules.
//! Users can either import this for everything, or import specific modules.
//!
//! Example - Import everything:
//!   const quic = @import("quic-zig");
//!   const server = quic.server.Server;
//!
//! Example - Import only what you need:
//!   const quic_server = @import("quic-zig-server");
//!   const server = quic_server.Server;

const std = @import("std");

// Re-export all modules
pub const core = @import("core/root.zig");
pub const client = @import("client/root.zig");
pub const server = @import("server/root.zig");
pub const crypto = @import("crypto/root.zig");
pub const utils = @import("utils/root.zig");

// Re-export commonly used types at top level for convenience
pub const Connection = core.Connection;
pub const Stream = core.Stream;
pub const Packet = core.Packet;
pub const Client = client.Client;
pub const Server = server.Server;
pub const VarInt = utils.VarInt;
pub const ConnectionId = utils.ConnectionId;

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    std.debug.print("\n=== Main Module Tests ===\n", .{});
    try std.testing.expect(add(3, 7) == 10);
    std.debug.print("✓ Main module test passed\n", .{});
}
