//! QUIC Header Types and Structures
//!
//! This module implements QUIC packet headers according to RFC 9000 Section 17.
//! Headers are the first part of every QUIC packet and contain routing information.

const std = @import("std");

pub const HeaderType = enum {
    HETY_SHORT,      // Short header (1-RTT packets)
    HETY_VERNEG,     // Version Negotiation
    HETY_INITIAL,    // Initial packet
    HETY_RETRY,      // Retry packet
    HETY_HANDSHAKE,  // Handshake packet
    HETY_0RTT,       // 0-RTT early data
};

/// RFC 9000 Section 17.2 - Long Header Format
/// Used for Initial, 0-RTT, Handshake, and Retry packets
pub const LongHeader = struct {
    header_type: HeaderType,
    version: u32,
    dest_conn_id: []const u8,
    src_conn_id: []const u8,
    token: ?[]const u8 = null,  // Only for Initial packets
    length: u64,  // Payload length (as VarInt)
    packet_number: u32,

    pub fn toBytes(self: LongHeader, buffer: []u8) !usize {
        _ = self;
        _ = buffer;
        // TODO: Implement long header serialization per RFC 9000 Section 17.2
        return error.NotImplemented;
    }

    pub fn size(self: LongHeader) usize {
        _ = self;
        // TODO: Calculate size including VarInt encoding
        return 0;
    }
};

/// RFC 9000 Section 17.3 - Short Header Format
/// Used for 1-RTT packets
pub const ShortHeader = struct {
    dest_conn_id: []const u8,
    packet_number: u32,

    pub fn toBytes(self: ShortHeader, buffer: []u8) !usize {
        _ = self;
        _ = buffer;
        // TODO: Implement short header serialization per RFC 9000 Section 17.3
        return error.NotImplemented;
    }

    pub fn size(self: ShortHeader) usize {
        _ = self;
        // TODO: Calculate size
        return 0;
    }
};

/// Version Negotiation packet header (stubbed)
pub const VersionNegHeader = struct {
    supported_versions: []const u32,

    pub fn toBytes(self: VersionNegHeader, buffer: []u8) !usize {
        _ = self;
        _ = buffer;
        // TODO: Implement version negotiation header
        return error.NotImplemented;
    }

    pub fn size(self: VersionNegHeader) usize {
        _ = self;
        return 0;
    }
};

/// Retry packet header (stubbed)
pub const RetryHeader = struct {
    pub fn toBytes(self: RetryHeader, buffer: []u8) !usize {
        _ = self;
        _ = buffer;
        // TODO: Implement retry header
        return error.NotImplemented;
    }

    pub fn size(self: RetryHeader) usize {
        _ = self;
        return 0;
    }
};

/// Tagged union containing all header types
pub const Header = union(HeaderType) {
    HETY_SHORT: ShortHeader,
    HETY_VERNEG: VersionNegHeader,
    HETY_INITIAL: LongHeader,
    HETY_RETRY: RetryHeader,
    HETY_HANDSHAKE: LongHeader,
    HETY_0RTT: LongHeader,

    /// Serialize header to bytes
    pub fn toBytes(self: Header, buffer: []u8) !usize {
        return switch (self) {
            .HETY_SHORT => |h| h.toBytes(buffer),
            .HETY_INITIAL => |h| h.toBytes(buffer),
            .HETY_HANDSHAKE => |h| h.toBytes(buffer),
            .HETY_0RTT => |h| h.toBytes(buffer),
            .HETY_VERNEG => |h| h.toBytes(buffer),
            .HETY_RETRY => |h| h.toBytes(buffer),
        };
    }

    /// Calculate header size in bytes
    pub fn size(self: Header) usize {
        return switch (self) {
            .HETY_SHORT => |h| h.size(),
            .HETY_INITIAL => |h| h.size(),
            .HETY_HANDSHAKE => |h| h.size(),
            .HETY_0RTT => |h| h.size(),
            .HETY_VERNEG => |h| h.size(),
            .HETY_RETRY => |h| h.size(),
        };
    }
};

// Tests
test "LongHeader.size returns 0 (stubbed)" {
    const header = LongHeader{
        .header_type = .HETY_INITIAL,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{1, 2, 3, 4},
        .src_conn_id = &[_]u8{5, 6, 7, 8},
        .length = 100,
        .packet_number = 1,
    };
    try std.testing.expectEqual(@as(usize, 0), header.size());
}

test "ShortHeader.size returns 0 (stubbed)" {
    const header = ShortHeader{
        .dest_conn_id = &[_]u8{1, 2, 3, 4},
        .packet_number = 1,
    };
    try std.testing.expectEqual(@as(usize, 0), header.size());
}

test "Header union with SHORT header" {
    const header = Header{
        .HETY_SHORT = ShortHeader{
            .dest_conn_id = &[_]u8{1, 2, 3, 4},
            .packet_number = 1,
        },
    };
    try std.testing.expectEqual(@as(usize, 0), header.size());
}

test "Header union with INITIAL header" {
    const header = Header{
        .HETY_INITIAL = LongHeader{
            .header_type = .HETY_INITIAL,
            .version = 0x00000001,
            .dest_conn_id = &[_]u8{1, 2, 3, 4},
            .src_conn_id = &[_]u8{5, 6, 7, 8},
            .length = 100,
            .packet_number = 1,
        },
    };
    try std.testing.expectEqual(@as(usize, 0), header.size());
}

test "Header.toBytes returns NotImplemented (stubbed)" {
    const header = Header{
        .HETY_SHORT = ShortHeader{
            .dest_conn_id = &[_]u8{1, 2, 3, 4},
            .packet_number = 1,
        },
    };
    var buffer: [256]u8 = undefined;
    try std.testing.expectError(error.NotImplemented, header.toBytes(&buffer));
}
