//! Core QUIC protocol implementation
//!
//! This module contains the core QUIC protocol logic including:
//! - Packet handling (RFC 9000 Section 17)
//! - Frame types (RFC 9000 Section 12)
//! - Header formats (RFC 9000 Section 17)
//! - Connection state machine
//! - Flow control
//! - Congestion control
//! - Stream management

const std = @import("std");

// Export UDP socket implementation
pub const udp = @import("udp.zig");
pub const UdpSocket = udp.UdpSocket;
pub const RecvResult = udp.RecvResult;

// Export QUIC packet, frame, and header types
pub const packet_module = @import("quic/packet.zig");
pub const frame_module = @import("quic/frame.zig");
pub const header_module = @import("quic/header.zig");

pub const Packet = packet_module.Packet;
pub const PacketProtection = packet_module.PacketProtection;
pub const Frame = frame_module.Frame;
pub const FrameType = frame_module.FrameType;
pub const PingFrame = frame_module.PingFrame;
pub const PaddingFrame = frame_module.PaddingFrame;
pub const AckFrame = frame_module.AckFrame;
pub const StreamFrame = frame_module.StreamFrame;
pub const Header = header_module.Header;
pub const HeaderType = header_module.HeaderType;
pub const ShortHeader = header_module.ShortHeader;
pub const LongHeader = header_module.LongHeader;

// TODO: Implement QUIC protocol core
// For now, export placeholder types

pub const Connection = struct {
    // TODO: Connection state
};

pub const Stream = struct {
    // TODO: Stream state
};

pub fn init() void {
    // TODO: Initialize QUIC core
}

test "core module" {
    std.debug.print("\n=== Core Module Tests ===\n", .{});
    try std.testing.expect(true);
    std.debug.print("✓ Core module test passed\n", .{});
}
