//! Core QUIC protocol implementation
//!
//! This module contains the core QUIC protocol logic including:
//! - Packet handling
//! - Connection state machine
//! - Flow control
//! - Congestion control
//! - Stream management

const std = @import("std");

// Export UDP socket implementation
pub const udp = @import("udp.zig");
pub const UdpSocket = udp.UdpSocket;
pub const RecvResult = udp.RecvResult;

// TODO: Implement QUIC protocol core
// For now, export placeholder types

pub const Connection = struct {
    // TODO: Connection state
};

pub const Stream = struct {
    // TODO: Stream state
};

pub const Packet = struct {
    // TODO: Packet structure
};

pub fn init() void {
    // TODO: Initialize QUIC core
}

test "core module" {
    std.debug.print("\n=== Core Module Tests ===\n", .{});
    try std.testing.expect(true);
    std.debug.print("✓ Core module test passed\n", .{});
}
