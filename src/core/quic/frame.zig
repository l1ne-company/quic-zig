//! QUIC Frame Types and Structures
//!
//! This module implements QUIC frame types according to RFC 9000 Section 12.
//! Frames are the basic unit of communication in QUIC.

const std = @import("std");

/// RFC 9000 Section 12.4 - Frame Types
pub const FrameType = enum(u8) {
    PADDING = 0x00,
    PING = 0x01,
    ACK = 0x02,
    ACK_ECN = 0x03,
    RESET_STREAM = 0x04,
    STOP_SENDING = 0x05,
    CRYPTO = 0x06,
    NEW_TOKEN = 0x07,
    STREAM = 0x08,
    MAX_DATA = 0x10,
    MAX_STREAM_DATA = 0x11,
    MAX_STREAMS_BIDI = 0x12,
    MAX_STREAMS_UNI = 0x13,
    DATA_BLOCKED = 0x14,
    STREAM_DATA_BLOCKED = 0x15,
    STREAMS_BLOCKED_BIDI = 0x16,
    STREAMS_BLOCKED_UNI = 0x17,
    NEW_CONNECTION_ID = 0x18,
    RETIRE_CONNECTION_ID = 0x19,
    PATH_CHALLENGE = 0x1a,
    PATH_RESPONSE = 0x1b,
    CONNECTION_CLOSE = 0x1c,
    CONNECTION_CLOSE_APP = 0x1d,
    HANDSHAKE_DONE = 0x1e,
};

/// PING frame - RFC 9000 Section 12.5
/// Used to keep a connection alive and measure round-trip time
pub const PingFrame = struct {
    pub fn toBytes(self: PingFrame, buffer: []u8) !usize {
        _ = self;
        if (buffer.len < 1) return error.BufferTooSmall;
        buffer[0] = @intFromEnum(FrameType.PING);
        return 1;
    }

    pub fn size(self: PingFrame) usize {
        _ = self;
        return 1;
    }
};

/// PADDING frame - RFC 9000 Section 12.7
/// Used to pad packets to a desired size
pub const PaddingFrame = struct {
    /// Number of PADDING bytes to write
    count: usize,

    pub fn toBytes(self: PaddingFrame, buffer: []u8) !usize {
        if (buffer.len < self.count) return error.BufferTooSmall;
        @memset(buffer[0..self.count], 0x00);
        return self.count;
    }

    pub fn size(self: PaddingFrame) usize {
        return self.count;
    }
};

/// ACK frame - RFC 9000 Section 12.6
/// Acknowledges packets received (simplified for now)
pub const AckFrame = struct {
    largest_acked: u64,
    ack_delay: u64,

    pub fn toBytes(self: AckFrame, buffer: []u8) !usize {
        _ = self;
        _ = buffer;
        // TODO: Implement ACK frame serialization with VarInt encoding
        return error.NotImplemented;
    }

    pub fn size(self: AckFrame) usize {
        _ = self;
        // TODO: Calculate actual size with VarInt encoding
        return 0;
    }
};

/// STREAM frame - RFC 9000 Section 12.8
/// Carries stream data (simplified, stubs for now)
pub const StreamFrame = struct {
    stream_id: u64,
    offset: u64,
    data: []const u8,
    fin: bool,

    pub fn toBytes(self: StreamFrame, buffer: []u8) !usize {
        _ = self;
        _ = buffer;
        // TODO: Implement STREAM frame serialization
        return error.NotImplemented;
    }

    pub fn size(self: StreamFrame) usize {
        _ = self;
        // TODO: Calculate actual size
        return 0;
    }
};

/// Tagged union of all frame types
/// This allows treating different frame types uniformly
pub const Frame = union(FrameType) {
    PADDING: PaddingFrame,
    PING: PingFrame,
    ACK: AckFrame,
    ACK_ECN: void,
    RESET_STREAM: void,
    STOP_SENDING: void,
    CRYPTO: void,
    NEW_TOKEN: void,
    STREAM: StreamFrame,
    MAX_DATA: void,
    MAX_STREAM_DATA: void,
    MAX_STREAMS_BIDI: void,
    MAX_STREAMS_UNI: void,
    DATA_BLOCKED: void,
    STREAM_DATA_BLOCKED: void,
    STREAMS_BLOCKED_BIDI: void,
    STREAMS_BLOCKED_UNI: void,
    NEW_CONNECTION_ID: void,
    RETIRE_CONNECTION_ID: void,
    PATH_CHALLENGE: void,
    PATH_RESPONSE: void,
    CONNECTION_CLOSE: void,
    CONNECTION_CLOSE_APP: void,
    HANDSHAKE_DONE: void,

    /// Serialize frame to bytes
    pub fn toBytes(self: Frame, buffer: []u8) !usize {
        return switch (self) {
            .PING => |frame| frame.toBytes(buffer),
            .PADDING => |frame| frame.toBytes(buffer),
            .ACK => |frame| frame.toBytes(buffer),
            .STREAM => |frame| frame.toBytes(buffer),
            else => error.NotImplemented,
        };
    }

    /// Calculate frame size in bytes
    pub fn size(self: Frame) usize {
        return switch (self) {
            .PING => |frame| frame.size(),
            .PADDING => |frame| frame.size(),
            .ACK => |frame| frame.size(),
            .STREAM => |frame| frame.size(),
            else => 0,
        };
    }
};

// Tests
test "PingFrame.toBytes" {
    const ping = PingFrame{};
    var buffer: [64]u8 = undefined;

    const bytes_written = try ping.toBytes(&buffer);
    try std.testing.expectEqual(@as(usize, 1), bytes_written);
    try std.testing.expectEqual(@as(u8, 0x01), buffer[0]);
}

test "PingFrame.size" {
    const ping = PingFrame{};
    try std.testing.expectEqual(@as(usize, 1), ping.size());
}

test "PaddingFrame.toBytes with 1 byte" {
    const padding = PaddingFrame{ .count = 1 };
    var buffer: [64]u8 = undefined;

    const bytes_written = try padding.toBytes(&buffer);
    try std.testing.expectEqual(@as(usize, 1), bytes_written);
    try std.testing.expectEqual(@as(u8, 0x00), buffer[0]);
}

test "PaddingFrame.toBytes with 10 bytes" {
    const padding = PaddingFrame{ .count = 10 };
    var buffer: [64]u8 = undefined;

    const bytes_written = try padding.toBytes(&buffer);
    try std.testing.expectEqual(@as(usize, 10), bytes_written);
    for (buffer[0..10]) |byte| {
        try std.testing.expectEqual(@as(u8, 0x00), byte);
    }
}

test "PaddingFrame.size" {
    const padding = PaddingFrame{ .count = 50 };
    try std.testing.expectEqual(@as(usize, 50), padding.size());
}

test "PaddingFrame.toBytes buffer too small" {
    const padding = PaddingFrame{ .count = 100 };
    var buffer: [50]u8 = undefined;

    try std.testing.expectError(error.BufferTooSmall, padding.toBytes(&buffer));
}

test "Frame union PING serialization" {
    const frame = Frame{ .PING = PingFrame{} };
    var buffer: [64]u8 = undefined;

    const bytes_written = try frame.toBytes(&buffer);
    try std.testing.expectEqual(@as(usize, 1), bytes_written);
    try std.testing.expectEqual(@as(u8, 0x01), buffer[0]);
}

test "Frame union PADDING serialization" {
    const frame = Frame{ .PADDING = PaddingFrame{ .count = 5 } };
    var buffer: [64]u8 = undefined;

    const bytes_written = try frame.toBytes(&buffer);
    try std.testing.expectEqual(@as(usize, 5), bytes_written);
    for (buffer[0..5]) |byte| {
        try std.testing.expectEqual(@as(u8, 0x00), byte);
    }
}

test "Frame union size calculation" {
    const ping_frame = Frame{ .PING = PingFrame{} };
    try std.testing.expectEqual(@as(usize, 1), ping_frame.size());

    const padding_frame = Frame{ .PADDING = PaddingFrame{ .count = 25 } };
    try std.testing.expectEqual(@as(usize, 25), padding_frame.size());
}

test "Frame union not implemented frames return error" {
    const frame = Frame{ .ACK = AckFrame{ .largest_acked = 0, .ack_delay = 0 } };
    var buffer: [64]u8 = undefined;

    try std.testing.expectError(error.NotImplemented, frame.toBytes(&buffer));
}
