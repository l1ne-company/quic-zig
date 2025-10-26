//! QUIC Utilities
//!
//! This module contains utility functions used across the QUIC implementation

const std = @import("std");

pub const VarInt = struct {
    pub fn encode(value: u64, buf: []u8) !usize {
        _ = value;
        _ = buf;
        // TODO: Implement variable-length integer encoding
        return error.NotImplemented;
    }

    pub fn decode(buf: []const u8) !struct { value: u64, len: usize } {
        _ = buf;
        // TODO: Implement variable-length integer decoding
        return error.NotImplemented;
    }
};

pub const ConnectionId = struct {
    bytes: []const u8,

    pub fn generate(allocator: std.mem.Allocator, len: usize) !ConnectionId {
        _ = allocator;
        _ = len;
        // TODO: Generate random connection ID
        return error.NotImplemented;
    }
};

test "utils module" {
    try std.testing.expect(true);
}
