//! QUIC Utilities
//!
//! This module contains utility functions used across the QUIC implementation

const std = @import("std");

pub const VarInt = struct {
    /// Encode a 64-bit integer as a variable-length integer per RFC 9000 Section 16
    /// Returns the number of bytes written
    pub fn encode(value: u64, buf: []u8) !usize {
        // 1-byte encoding (0-63): 0b00xxxxxx
        if (value < 64) {
            if (buf.len < 1) return error.BufferTooSmall;
            buf[0] = @intCast(value & 0x3f);
            return 1;
        }

        // 2-byte encoding (0-16383): 0b01xxxxxx xxxxxxxx
        if (value < 16384) {
            if (buf.len < 2) return error.BufferTooSmall;
            const val = value & 0x3fff;
            buf[0] = @intCast((val >> 8) | 0x40);
            buf[1] = @intCast(val & 0xff);
            return 2;
        }

        // 4-byte encoding (0-1073741823): 0b10xxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
        if (value < 1073741824) {
            if (buf.len < 4) return error.BufferTooSmall;
            const val = value & 0x3fffffff;
            buf[0] = @intCast((val >> 24) | 0x80);
            buf[1] = @intCast((val >> 16) & 0xff);
            buf[2] = @intCast((val >> 8) & 0xff);
            buf[3] = @intCast(val & 0xff);
            return 4;
        }

        // 8-byte encoding: 0b11xxxxxx ... (0-4611686018427387903)
        if (buf.len < 8) return error.BufferTooSmall;
        const val = value & 0x3fffffffffffffff;
        buf[0] = @intCast((val >> 56) | 0xc0);
        buf[1] = @intCast((val >> 48) & 0xff);
        buf[2] = @intCast((val >> 40) & 0xff);
        buf[3] = @intCast((val >> 32) & 0xff);
        buf[4] = @intCast((val >> 24) & 0xff);
        buf[5] = @intCast((val >> 16) & 0xff);
        buf[6] = @intCast((val >> 8) & 0xff);
        buf[7] = @intCast(val & 0xff);
        return 8;
    }

    /// Decode a variable-length integer per RFC 9000 Section 16
    /// Returns the decoded value and number of bytes read
    pub fn decode(buf: []const u8) !struct { value: u64, len: usize } {
        if (buf.len < 1) return error.BufferTooSmall;

        const first_byte = buf[0];
        const prefix = (first_byte >> 6) & 0x3;

        switch (prefix) {
            // 1-byte encoding: 0b00xxxxxx
            0b00 => {
                return .{ .value = first_byte & 0x3f, .len = 1 };
            },
            // 2-byte encoding: 0b01xxxxxx xxxxxxxx
            0b01 => {
                if (buf.len < 2) return error.BufferTooSmall;
                const value = ((@as(u64, first_byte & 0x3f) << 8) | buf[1]);
                return .{ .value = value, .len = 2 };
            },
            // 4-byte encoding: 0b10xxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
            0b10 => {
                if (buf.len < 4) return error.BufferTooSmall;
                const value = ((@as(u64, first_byte & 0x3f) << 24) |
                    (@as(u64, buf[1]) << 16) |
                    (@as(u64, buf[2]) << 8) |
                    buf[3]);
                return .{ .value = value, .len = 4 };
            },
            // 8-byte encoding: 0b11xxxxxx ... xxxxxxxx
            0b11 => {
                if (buf.len < 8) return error.BufferTooSmall;
                const value = ((@as(u64, first_byte & 0x3f) << 56) |
                    (@as(u64, buf[1]) << 48) |
                    (@as(u64, buf[2]) << 40) |
                    (@as(u64, buf[3]) << 32) |
                    (@as(u64, buf[4]) << 24) |
                    (@as(u64, buf[5]) << 16) |
                    (@as(u64, buf[6]) << 8) |
                    buf[7]);
                return .{ .value = value, .len = 8 };
            },
            else => return error.InvalidPrefix,
        }
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

test "VarInt.encode 1-byte (0-63)" {
    var buf: [8]u8 = undefined;

    // Test 0
    const len1 = try VarInt.encode(0, &buf);
    try std.testing.expectEqual(@as(usize, 1), len1);
    try std.testing.expectEqual(@as(u8, 0x00), buf[0]);

    // Test 25
    const len2 = try VarInt.encode(25, &buf);
    try std.testing.expectEqual(@as(usize, 1), len2);
    try std.testing.expectEqual(@as(u8, 25), buf[0]);

    // Test 63 (max 1-byte value)
    const len3 = try VarInt.encode(63, &buf);
    try std.testing.expectEqual(@as(usize, 1), len3);
    try std.testing.expectEqual(@as(u8, 0x3f), buf[0]);
}

test "VarInt.encode 2-byte (64-16383)" {
    var buf: [8]u8 = undefined;

    // Test 64 (min 2-byte value)
    const len1 = try VarInt.encode(64, &buf);
    try std.testing.expectEqual(@as(usize, 2), len1);
    try std.testing.expectEqual(@as(u8, 0x40), buf[0]);
    try std.testing.expectEqual(@as(u8, 64), buf[1]);

    // Test 16383 (max 2-byte value)
    const len2 = try VarInt.encode(16383, &buf);
    try std.testing.expectEqual(@as(usize, 2), len2);
    try std.testing.expectEqual(@as(u8, 0x7f), buf[0]);
    try std.testing.expectEqual(@as(u8, 0xff), buf[1]);

    // Test 1000
    const len3 = try VarInt.encode(1000, &buf);
    try std.testing.expectEqual(@as(usize, 2), len3);
}

test "VarInt.encode 4-byte (16384-1073741823)" {
    var buf: [8]u8 = undefined;

    // Test 16384 (min 4-byte value)
    const len1 = try VarInt.encode(16384, &buf);
    try std.testing.expectEqual(@as(usize, 4), len1);
    try std.testing.expectEqual(@as(u8, 0x80), buf[0]);
    try std.testing.expectEqual(@as(u8, 0x00), buf[1]);
    try std.testing.expectEqual(@as(u8, 0x40), buf[2]);
    try std.testing.expectEqual(@as(u8, 0x00), buf[3]);

    // Test 1073741823 (max 4-byte value)
    const len2 = try VarInt.encode(1073741823, &buf);
    try std.testing.expectEqual(@as(usize, 4), len2);

    // Test 500000
    const len3 = try VarInt.encode(500000, &buf);
    try std.testing.expectEqual(@as(usize, 4), len3);
}

test "VarInt.encode 8-byte" {
    var buf: [8]u8 = undefined;

    // Test 1073741824 (min 8-byte value)
    const len1 = try VarInt.encode(1073741824, &buf);
    try std.testing.expectEqual(@as(usize, 8), len1);
    try std.testing.expectEqual(@as(u8, 0xc0), buf[0]);

    // Test large value
    const len2 = try VarInt.encode(0x123456789abcdef0, &buf);
    try std.testing.expectEqual(@as(usize, 8), len2);
}

test "VarInt.encode buffer too small" {
    var buf: [1]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, VarInt.encode(64, &buf));
}

test "VarInt.decode 1-byte" {
    var buf: [8]u8 = undefined;

    buf[0] = 0x00;
    const result1 = try VarInt.decode(&buf);
    try std.testing.expectEqual(@as(u64, 0), result1.value);
    try std.testing.expectEqual(@as(usize, 1), result1.len);

    buf[0] = 0x3f;
    const result2 = try VarInt.decode(&buf);
    try std.testing.expectEqual(@as(u64, 63), result2.value);
    try std.testing.expectEqual(@as(usize, 1), result2.len);
}

test "VarInt.decode 2-byte" {
    var buf: [8]u8 = undefined;

    buf[0] = 0x40;
    buf[1] = 0x64;
    const result1 = try VarInt.decode(&buf);
    try std.testing.expectEqual(@as(u64, 100), result1.value);
    try std.testing.expectEqual(@as(usize, 2), result1.len);

    buf[0] = 0x7f;
    buf[1] = 0xff;
    const result2 = try VarInt.decode(&buf);
    try std.testing.expectEqual(@as(u64, 16383), result2.value);
    try std.testing.expectEqual(@as(usize, 2), result2.len);
}

test "VarInt.decode 4-byte" {
    var buf: [8]u8 = undefined;

    buf[0] = 0x80;
    buf[1] = 0x00;
    buf[2] = 0x40;
    buf[3] = 0x00;
    const result1 = try VarInt.decode(&buf);
    try std.testing.expectEqual(@as(u64, 16384), result1.value);
    try std.testing.expectEqual(@as(usize, 4), result1.len);
}

test "VarInt.decode 8-byte" {
    var buf: [8]u8 = undefined;

    // Encode 1073741824 as 8-byte
    const encode_len = try VarInt.encode(1073741824, &buf);
    try std.testing.expectEqual(@as(usize, 8), encode_len);

    // Decode it back
    const result1 = try VarInt.decode(&buf);
    try std.testing.expectEqual(@as(u64, 1073741824), result1.value);
    try std.testing.expectEqual(@as(usize, 8), result1.len);
}

test "VarInt.decode buffer too small" {
    var buf: [1]u8 = undefined;
    buf[0] = 0x40; // 2-byte encoding
    try std.testing.expectError(error.BufferTooSmall, VarInt.decode(&buf));
}

test "VarInt round-trip encode/decode" {
    var buf: [8]u8 = undefined;

    const test_values = [_]u64{ 0, 25, 63, 64, 1000, 16383, 16384, 500000, 1073741823, 1073741824, 0x123456789abcdef0 };

    for (test_values) |value| {
        const encode_len = try VarInt.encode(value, &buf);
        const decode_result = try VarInt.decode(buf[0..encode_len]);
        try std.testing.expectEqual(value, decode_result.value);
        try std.testing.expectEqual(encode_len, decode_result.len);
    }
}

test "utils module" {
    std.debug.print("\n=== Utils Module Tests ===\n", .{});
    try std.testing.expect(true);
    std.debug.print("✓ Utils module test passed\n", .{});
}
