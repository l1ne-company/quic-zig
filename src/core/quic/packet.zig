//! QUIC Packet Structure
//!
//! This module implements QUIC packets according to RFC 9000 Section 17.
//! A packet consists of a header followed by one or more frames (the payload).

const std = @import("std");
const frame_module = @import("frame.zig");
const header_module = @import("header.zig");

pub const Frame = frame_module.Frame;
pub const Header = header_module.Header;

/// QUIC Packet - contains a header and one or more frames
pub const Packet = struct {
    header: Header,
    frames: []Frame,
    frames_capacity: usize,
    frames_count: usize,
    allocator: std.mem.Allocator,

    /// Create a new packet with the given header
    pub fn init(allocator: std.mem.Allocator, hdr: Header) Packet {
        return Packet{
            .header = hdr,
            .frames = &.{},
            .frames_capacity = 0,
            .frames_count = 0,
            .allocator = allocator,
        };
    }

    /// Free packet resources
    pub fn deinit(self: *Packet) void {
        if (self.frames.len > 0) {
            self.allocator.free(self.frames);
        }
    }

    /// Add a frame to the packet
    pub fn addFrame(self: *Packet, new_frame: Frame) !void {
        if (self.frames_count >= self.frames_capacity) {
            const new_capacity = if (self.frames_capacity == 0) 4 else self.frames_capacity * 2;
            const new_frames = try self.allocator.alloc(Frame, new_capacity);
            if (self.frames_count > 0) {
                @memcpy(new_frames[0..self.frames_count], self.frames[0..self.frames_count]);
                self.allocator.free(self.frames);
            }
            self.frames = new_frames;
            self.frames_capacity = new_capacity;
        }
        self.frames[self.frames_count] = new_frame;
        self.frames_count += 1;
    }

    /// Calculate total packet size (header + all frames)
    pub fn size(self: Packet) usize {
        var total: usize = self.header.size();
        for (self.frames[0..self.frames_count]) |f| {
            total += f.size();
        }
        return total;
    }

    /// Serialize packet to bytes (header + frame payload)
    /// Buffer must be large enough for the entire packet (use size() to calculate)
    pub fn toBytes(self: Packet, buffer: []u8) !usize {
        var offset: usize = 0;

        // Serialize header
        const header_len = try self.header.toBytes(buffer[offset..]);
        offset += header_len;

        // Serialize frames (payload - will be encrypted in future)
        for (self.frames[0..self.frames_count]) |f| {
            const frame_len = try f.toBytes(buffer[offset..]);
            offset += frame_len;
        }

        return offset;
    }

    /// Send packet over UDP socket
    /// Allocates buffer internally for serialization
    pub fn send(self: Packet, socket: anytype, dest_addr: std.net.Address, allocator: std.mem.Allocator) !usize {
        const packet_size = self.size();

        // Allocate buffer for serialized packet
        const buffer = try allocator.alloc(u8, packet_size);
        defer allocator.free(buffer);

        // Serialize packet
        const bytes_written = try self.toBytes(buffer);

        // Send via UDP
        return socket.send(buffer[0..bytes_written], dest_addr);
    }
};

/// Packet protection stub - will be implemented with crypto module
pub const PacketProtection = struct {
    /// Apply packet protection (encryption + header protection)
    /// Per RFC 9001 - Packet Protection
    pub fn protect(packet_bytes: []u8) !void {
        _ = packet_bytes;
        // TODO: Call crypto module for encryption per RFC 9001
        // For now, packets are sent unencrypted (for testing only)
    }

    /// Remove packet protection (decryption + header protection removal)
    /// Per RFC 9001 - Packet Protection
    pub fn unprotect(packet_bytes: []u8) !void {
        _ = packet_bytes;
        // TODO: Call crypto module for decryption per RFC 9001
    }
};

// Tests
test "Packet.init and deinit" {
    const allocator = std.testing.allocator;
    const hdr = Header{
        .HETY_SHORT = header_module.ShortHeader{
            .dest_conn_id = &[_]u8{1, 2, 3, 4},
            .packet_number = 1,
        },
    };

    var packet = Packet.init(allocator, hdr);
    defer packet.deinit();

    try std.testing.expectEqual(@as(usize, 0), packet.frames_count);
}

test "Packet.addFrame single frame" {
    const allocator = std.testing.allocator;
    const hdr = Header{
        .HETY_SHORT = header_module.ShortHeader{
            .dest_conn_id = &[_]u8{1, 2, 3, 4},
            .packet_number = 1,
        },
    };

    var packet = Packet.init(allocator, hdr);
    defer packet.deinit();

    try packet.addFrame(Frame{ .PING = frame_module.PingFrame{} });
    try std.testing.expectEqual(@as(usize, 1), packet.frames_count);
}

test "Packet.addFrame multiple frames" {
    const allocator = std.testing.allocator;
    const hdr = Header{
        .HETY_SHORT = header_module.ShortHeader{
            .dest_conn_id = &[_]u8{1, 2, 3, 4},
            .packet_number = 1,
        },
    };

    var packet = Packet.init(allocator, hdr);
    defer packet.deinit();

    try packet.addFrame(Frame{ .PING = frame_module.PingFrame{} });
    try packet.addFrame(Frame{ .PADDING = frame_module.PaddingFrame{ .count = 10 } });
    try packet.addFrame(Frame{ .PING = frame_module.PingFrame{} });

    try std.testing.expectEqual(@as(usize, 3), packet.frames_count);
}

test "Packet.size with frames" {
    const allocator = std.testing.allocator;
    const hdr = Header{
        .HETY_SHORT = header_module.ShortHeader{
            .dest_conn_id = &[_]u8{1, 2, 3, 4},
            .packet_number = 1,
        },
    };

    var packet = Packet.init(allocator, hdr);
    defer packet.deinit();

    try packet.addFrame(Frame{ .PING = frame_module.PingFrame{} });
    try packet.addFrame(Frame{ .PADDING = frame_module.PaddingFrame{ .count = 10 } });

    // Size should be header (0, stubbed) + PING (1) + PADDING (10)
    const expected_size = 0 + 1 + 10;
    try std.testing.expectEqual(expected_size, packet.size());
}

test "Packet.toBytes with PING frame" {
    const allocator = std.testing.allocator;
    const hdr = Header{
        .HETY_SHORT = header_module.ShortHeader{
            .dest_conn_id = &[_]u8{1, 2, 3, 4},
            .packet_number = 1,
        },
    };

    var packet = Packet.init(allocator, hdr);
    defer packet.deinit();

    try packet.addFrame(Frame{ .PING = frame_module.PingFrame{} });

    var buffer: [64]u8 = undefined;

    // Should fail because header.toBytes is stubbed
    try std.testing.expectError(error.NotImplemented, packet.toBytes(&buffer));
}

test "Packet.toBytes with multiple frames" {
    const allocator = std.testing.allocator;
    const hdr = Header{
        .HETY_SHORT = header_module.ShortHeader{
            .dest_conn_id = &[_]u8{1, 2, 3, 4},
            .packet_number = 1,
        },
    };

    var packet = Packet.init(allocator, hdr);
    defer packet.deinit();

    try packet.addFrame(Frame{ .PING = frame_module.PingFrame{} });
    try packet.addFrame(Frame{ .PADDING = frame_module.PaddingFrame{ .count = 5 } });

    var buffer: [64]u8 = undefined;

    // Should fail because header.toBytes is stubbed
    try std.testing.expectError(error.NotImplemented, packet.toBytes(&buffer));
}

test "Packet with empty frames" {
    const allocator = std.testing.allocator;
    const hdr = Header{
        .HETY_SHORT = header_module.ShortHeader{
            .dest_conn_id = &[_]u8{1, 2, 3, 4},
            .packet_number = 1,
        },
    };

    var packet = Packet.init(allocator, hdr);
    defer packet.deinit();

    // Packet with no frames, should still have size of header (which is 0 when stubbed)
    try std.testing.expectEqual(@as(usize, 0), packet.size());
}

test "PacketProtection stubs" {
    var buffer: [64]u8 = undefined;
    buffer[0] = 0x01;

    // Should succeed (no-op stubs)
    try PacketProtection.protect(&buffer);
    try PacketProtection.unprotect(&buffer);
}
