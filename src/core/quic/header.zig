//! QUIC Header Types and Structures
//!
//! This module implements QUIC packet headers according to RFC 9000 Section 17.
//! Headers are the first part of every QUIC packet and contain routing information.

const std = @import("std");
const VarInt = @import("utils").VarInt;

fn packetNumberLength(pn: u32) usize {
    if (pn <= 0xFF) return 1;
    if (pn <= 0xFFFF) return 2;
    if (pn <= 0xFFFFFF) return 3;
    return 4;
}

pub const HeaderType = enum {
    HETY_SHORT, // Short header (1-RTT packets)
    HETY_VERNEG, // Version Negotiation
    HETY_INITIAL, // Initial packet
    HETY_RETRY, // Retry packet
    HETY_HANDSHAKE, // Handshake packet
    HETY_0RTT, // 0-RTT early data
};

/// RFC 9000 Section 17.2 - Long Header Format
/// Used for Initial, 0-RTT, Handshake, and Retry packets
pub const LongHeader = struct {
    header_type: HeaderType,
    version: u32,
    dest_conn_id: []const u8,
    src_conn_id: []const u8,
    token: ?[]const u8 = null, // Only for Initial packets
    length: u64, // Payload length (as VarInt)
    packet_number: u32,

    pub fn size(self: LongHeader) usize {
        const pn_len = packetNumberLength(self.packet_number);
        const token_size: usize = if (self.header_type == .HETY_INITIAL) blk: {
            const tok_len: usize = if (self.token) |t| t.len else 0;
            break :blk VarInt.encodedSize(tok_len) + tok_len;
        } else 0;
        return 1 // first byte
        + 4 // version
        + 1 + self.dest_conn_id.len // dcid length prefix + dcid
        + 1 + self.src_conn_id.len // scid length prefix + scid
        + token_size // token length varint + token bytes (Initial only)
        + VarInt.encodedSize(self.length) // length field
        + pn_len; // packet number
    }

    pub fn toBytes(self: LongHeader, buffer: []u8) !usize {
        const needed = self.size();
        if (buffer.len < needed) return error.BufferTooSmall;

        const pn_len = packetNumberLength(self.packet_number);
        const packet_type_bits: u8 = switch (self.header_type) {
            .HETY_INITIAL => 0x00,
            .HETY_0RTT => 0x01,
            .HETY_HANDSHAKE => 0x02,
            .HETY_RETRY => 0x03,
            else => return error.InvalidHeaderType,
        };

        var pos: usize = 0;

        // First byte: 1|1|type(2)|reserved(2)|pn_len(2)
        buffer[pos] = 0xC0 | (packet_type_bits << 4) | @as(u8, @intCast(pn_len - 1));
        pos += 1;

        // Version (big-endian u32)
        buffer[pos] = @intCast((self.version >> 24) & 0xFF);
        buffer[pos + 1] = @intCast((self.version >> 16) & 0xFF);
        buffer[pos + 2] = @intCast((self.version >> 8) & 0xFF);
        buffer[pos + 3] = @intCast(self.version & 0xFF);
        pos += 4;

        // DCID Length + DCID
        buffer[pos] = @intCast(self.dest_conn_id.len);
        pos += 1;
        @memcpy(buffer[pos .. pos + self.dest_conn_id.len], self.dest_conn_id);
        pos += self.dest_conn_id.len;

        // SCID Length + SCID
        buffer[pos] = @intCast(self.src_conn_id.len);
        pos += 1;
        @memcpy(buffer[pos .. pos + self.src_conn_id.len], self.src_conn_id);
        pos += self.src_conn_id.len;

        // Token (Initial packets only)
        if (self.header_type == .HETY_INITIAL) {
            const token: []const u8 = if (self.token) |t| t else &[_]u8{};
            const tok_varint_len = try VarInt.encode(@as(u64, token.len), buffer[pos..]);
            pos += tok_varint_len;
            if (token.len > 0) {
                @memcpy(buffer[pos .. pos + token.len], token);
                pos += token.len;
            }
        }

        // Length (VarInt)
        const len_bytes = try VarInt.encode(self.length, buffer[pos..]);
        pos += len_bytes;

        // Packet Number (big-endian, 1-4 bytes)
        for (0..pn_len) |j| {
            const shift: u5 = @intCast((pn_len - 1 - j) * 8);
            buffer[pos + j] = @intCast((self.packet_number >> shift) & 0xFF);
        }
        pos += pn_len;

        return pos;
    }

    pub fn fromBytes(buf: []const u8, allocator: std.mem.Allocator) !struct { header: LongHeader, len: usize } {
        if (buf.len < 1) return error.BufferTooSmall;

        var pos: usize = 0;
        const first_byte = buf[pos];
        pos += 1;

        // Bits 5-4: Long Packet Type
        const packet_type_bits = (first_byte >> 4) & 0x03;
        const header_type: HeaderType = switch (packet_type_bits) {
            0x00 => .HETY_INITIAL,
            0x01 => .HETY_0RTT,
            0x02 => .HETY_HANDSHAKE,
            0x03 => .HETY_RETRY,
            else => unreachable,
        };

        // Bits 1-0: Packet Number Length - 1
        const pn_len: usize = @as(usize, first_byte & 0x03) + 1;

        // Version (4 bytes big-endian)
        if (buf.len < pos + 4) return error.BufferTooSmall;
        const version: u32 = (@as(u32, buf[pos]) << 24) |
            (@as(u32, buf[pos + 1]) << 16) |
            (@as(u32, buf[pos + 2]) << 8) |
            @as(u32, buf[pos + 3]);
        pos += 4;

        // DCID
        if (buf.len < pos + 1) return error.BufferTooSmall;
        const dcid_len: usize = @as(usize, buf[pos]);
        pos += 1;
        if (buf.len < pos + dcid_len) return error.BufferTooSmall;
        const dcid = try allocator.dupe(u8, buf[pos .. pos + dcid_len]);
        errdefer allocator.free(dcid);
        pos += dcid_len;

        // SCID
        if (buf.len < pos + 1) return error.BufferTooSmall;
        const scid_len: usize = @as(usize, buf[pos]);
        pos += 1;
        if (buf.len < pos + scid_len) return error.BufferTooSmall;
        const scid = try allocator.dupe(u8, buf[pos .. pos + scid_len]);
        errdefer allocator.free(scid);
        pos += scid_len;

        // Token (Initial only)
        var token: ?[]const u8 = null;
        if (header_type == .HETY_INITIAL) {
            const tok_varint = try VarInt.decode(buf[pos..]);
            pos += tok_varint.len;
            const tok_len: usize = @intCast(tok_varint.value);
            if (tok_len > 0) {
                if (buf.len < pos + tok_len) return error.BufferTooSmall;
                token = try allocator.dupe(u8, buf[pos .. pos + tok_len]);
                pos += tok_len;
            }
        }
        errdefer if (token) |t| allocator.free(t);

        // Length (VarInt)
        const length_result = try VarInt.decode(buf[pos..]);
        pos += length_result.len;

        // Packet Number (big-endian)
        if (buf.len < pos + pn_len) return error.BufferTooSmall;
        var packet_number: u32 = 0;
        for (0..pn_len) |j| {
            packet_number = (packet_number << 8) | @as(u32, buf[pos + j]);
        }
        pos += pn_len;

        return .{
            .header = LongHeader{
                .header_type = header_type,
                .version = version,
                .dest_conn_id = dcid,
                .src_conn_id = scid,
                .token = token,
                .length = length_result.value,
                .packet_number = packet_number,
            },
            .len = pos,
        };
    }

    pub fn deinit(self: LongHeader, allocator: std.mem.Allocator) void {
        allocator.free(self.dest_conn_id);
        allocator.free(self.src_conn_id);
        if (self.token) |t| allocator.free(t);
    }
};

/// RFC 9000 Section 17.3 - Short Header Format
/// Used for 1-RTT packets
pub const ShortHeader = struct {
    dest_conn_id: []const u8,
    packet_number: u32,

    pub fn size(self: ShortHeader) usize {
        return 1 + self.dest_conn_id.len + packetNumberLength(self.packet_number);
    }

    pub fn toBytes(self: ShortHeader, buffer: []u8) !usize {
        const pn_len = packetNumberLength(self.packet_number);
        const needed = 1 + self.dest_conn_id.len + pn_len;
        if (buffer.len < needed) return error.BufferTooSmall;

        var pos: usize = 0;

        // First byte: 0|1|spin(1)|reserved(2)|key_phase(1)|pn_len(2)
        buffer[pos] = 0x40 | @as(u8, @intCast(pn_len - 1));
        pos += 1;

        // DCID (no length prefix)
        @memcpy(buffer[pos .. pos + self.dest_conn_id.len], self.dest_conn_id);
        pos += self.dest_conn_id.len;

        // Packet Number (big-endian)
        for (0..pn_len) |j| {
            const shift: u5 = @intCast((pn_len - 1 - j) * 8);
            buffer[pos + j] = @intCast((self.packet_number >> shift) & 0xFF);
        }
        pos += pn_len;

        return pos;
    }

    pub fn fromBytes(buf: []const u8, conn_id_len: usize, allocator: std.mem.Allocator) !struct { header: ShortHeader, len: usize } {
        if (buf.len < 1 + conn_id_len) return error.BufferTooSmall;

        var pos: usize = 0;
        const first_byte = buf[pos];
        pos += 1;

        // DCID (length known from connection state, passed as conn_id_len)
        if (buf.len < pos + conn_id_len) return error.BufferTooSmall;
        const dcid = try allocator.dupe(u8, buf[pos .. pos + conn_id_len]);
        errdefer allocator.free(dcid);
        pos += conn_id_len;

        // Bits 1-0: Packet Number Length - 1
        const pn_len: usize = @as(usize, first_byte & 0x03) + 1;
        if (buf.len < pos + pn_len) return error.BufferTooSmall;
        var packet_number: u32 = 0;
        for (0..pn_len) |j| {
            packet_number = (packet_number << 8) | @as(u32, buf[pos + j]);
        }
        pos += pn_len;

        return .{
            .header = ShortHeader{
                .dest_conn_id = dcid,
                .packet_number = packet_number,
            },
            .len = pos,
        };
    }

    pub fn deinit(self: ShortHeader, allocator: std.mem.Allocator) void {
        allocator.free(self.dest_conn_id);
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

    /// Parse a header from bytes, dispatching on bit 7 of the first byte.
    /// conn_id_len is required for short headers (not encoded on wire).
    pub fn fromBytes(buf: []const u8, conn_id_len: usize, allocator: std.mem.Allocator) !struct { header: Header, len: usize } {
        if (buf.len < 1) return error.BufferTooSmall;
        if (buf[0] & 0x80 != 0) {
            // Long header (bit 7 = 1)
            const result = try LongHeader.fromBytes(buf, allocator);
            errdefer result.header.deinit(allocator);
            const header: Header = switch (result.header.header_type) {
                .HETY_INITIAL => Header{ .HETY_INITIAL = result.header },
                .HETY_0RTT => Header{ .HETY_0RTT = result.header },
                .HETY_HANDSHAKE => Header{ .HETY_HANDSHAKE = result.header },
                else => return error.UnsupportedHeaderType,
            };
            return .{ .header = header, .len = result.len };
        } else {
            // Short header (bit 7 = 0)
            const result = try ShortHeader.fromBytes(buf, conn_id_len, allocator);
            return .{ .header = Header{ .HETY_SHORT = result.header }, .len = result.len };
        }
    }

    /// Free any memory allocated for this header's variable-length fields.
    pub fn deinit(self: Header, allocator: std.mem.Allocator) void {
        switch (self) {
            .HETY_SHORT => |h| h.deinit(allocator),
            .HETY_INITIAL, .HETY_HANDSHAKE, .HETY_0RTT => |h| h.deinit(allocator),
            .HETY_VERNEG, .HETY_RETRY => {},
        }
    }
};

// Tests

test "LongHeader Initial size" {
    const header = LongHeader{
        .header_type = .HETY_INITIAL,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{ 1, 2, 3, 4 },
        .src_conn_id = &[_]u8{ 5, 6, 7, 8 },
        .token = null,
        .length = 100,
        .packet_number = 1,
    };
    // 1 + 4 + 1+4 + 1+4 + varint(0)+0 + varint(100) + 1 = 1+4+5+5+1+2+1 = 19
    try std.testing.expectEqual(@as(usize, 19), header.size());
}

test "LongHeader Handshake size" {
    const header = LongHeader{
        .header_type = .HETY_HANDSHAKE,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{ 1, 2, 3, 4 },
        .src_conn_id = &[_]u8{ 5, 6, 7, 8 },
        .token = null,
        .length = 50,
        .packet_number = 2,
    };
    // 1 + 4 + 1+4 + 1+4 + 0 (no token) + varint(50) + 1 = 17
    try std.testing.expectEqual(@as(usize, 17), header.size());
}

test "ShortHeader size" {
    const header = ShortHeader{
        .dest_conn_id = &[_]u8{ 0xAA, 0xBB },
        .packet_number = 42,
    };
    // 1 + 2 + 1 = 4
    try std.testing.expectEqual(@as(usize, 4), header.size());
}

test "Header union SHORT size and toBytes" {
    const sh = ShortHeader{
        .dest_conn_id = &[_]u8{ 1, 2, 3, 4 },
        .packet_number = 1,
    };
    const header = Header{ .HETY_SHORT = sh };
    try std.testing.expectEqual(@as(usize, 6), header.size());

    var buf: [6]u8 = undefined;
    const n = try header.toBytes(&buf);
    try std.testing.expectEqual(@as(usize, 6), n);
}

test "Header union INITIAL size and toBytes" {
    const lh = LongHeader{
        .header_type = .HETY_INITIAL,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{ 1, 2, 3, 4 },
        .src_conn_id = &[_]u8{ 5, 6, 7, 8 },
        .length = 100,
        .packet_number = 1,
    };
    const header = Header{ .HETY_INITIAL = lh };
    try std.testing.expectEqual(@as(usize, 19), header.size());

    var buf: [19]u8 = undefined;
    const n = try header.toBytes(&buf);
    try std.testing.expectEqual(@as(usize, 19), n);
}

test "LongHeader Initial known byte sequence" {
    const header = LongHeader{
        .header_type = .HETY_INITIAL,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{ 1, 2, 3, 4 },
        .src_conn_id = &[_]u8{ 5, 6, 7, 8 },
        .token = null,
        .length = 100,
        .packet_number = 1,
    };
    var buf: [64]u8 = undefined;
    const n = try header.toBytes(&buf);
    try std.testing.expectEqual(@as(usize, 19), n);

    const expected = [_]u8{
        0xC0, // long, initial, pn_len=1
        0x00, 0x00, 0x00, 0x01, // version
        0x04, // dcid_len
        0x01, 0x02, 0x03, 0x04, // dcid
        0x04, // scid_len
        0x05, 0x06, 0x07, 0x08, // scid
        0x00, // token_len = 0 (1-byte varint)
        0x40, 0x64, // length = 100 (2-byte varint)
        0x01, // packet_number
    };
    try std.testing.expectEqualSlices(u8, &expected, buf[0..n]);
}

test "ShortHeader known byte sequence" {
    const header = ShortHeader{
        .dest_conn_id = &[_]u8{ 0xAA, 0xBB },
        .packet_number = 42,
    };
    var buf: [16]u8 = undefined;
    const n = try header.toBytes(&buf);
    try std.testing.expectEqual(@as(usize, 4), n);

    const expected = [_]u8{
        0x40, // short header, fixed bit set, pn_len=1
        0xAA, 0xBB, // dcid
        0x2A, // packet_number = 42
    };
    try std.testing.expectEqualSlices(u8, &expected, buf[0..n]);
}

test "LongHeader Initial round-trip no token" {
    const allocator = std.testing.allocator;
    const original = LongHeader{
        .header_type = .HETY_INITIAL,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{ 1, 2, 3, 4 },
        .src_conn_id = &[_]u8{ 5, 6, 7, 8 },
        .token = null,
        .length = 100,
        .packet_number = 1,
    };

    var buf: [64]u8 = undefined;
    const n = try original.toBytes(&buf);

    const result = try LongHeader.fromBytes(buf[0..n], allocator);
    defer result.header.deinit(allocator);

    try std.testing.expectEqual(original.header_type, result.header.header_type);
    try std.testing.expectEqual(original.version, result.header.version);
    try std.testing.expectEqualSlices(u8, original.dest_conn_id, result.header.dest_conn_id);
    try std.testing.expectEqualSlices(u8, original.src_conn_id, result.header.src_conn_id);
    try std.testing.expectEqual(@as(?[]const u8, null), result.header.token);
    try std.testing.expectEqual(original.length, result.header.length);
    try std.testing.expectEqual(original.packet_number, result.header.packet_number);
    try std.testing.expectEqual(n, result.len);
}

test "LongHeader Initial round-trip with token" {
    const allocator = std.testing.allocator;
    const original = LongHeader{
        .header_type = .HETY_INITIAL,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{ 0x0A, 0x0B },
        .src_conn_id = &[_]u8{ 0x0C, 0x0D },
        .token = &[_]u8{ 0x10, 0x20, 0x30 },
        .length = 50,
        .packet_number = 0x42,
    };

    var buf: [64]u8 = undefined;
    const n = try original.toBytes(&buf);

    const result = try LongHeader.fromBytes(buf[0..n], allocator);
    defer result.header.deinit(allocator);

    try std.testing.expectEqual(original.header_type, result.header.header_type);
    try std.testing.expectEqual(original.version, result.header.version);
    try std.testing.expectEqualSlices(u8, original.dest_conn_id, result.header.dest_conn_id);
    try std.testing.expectEqualSlices(u8, original.src_conn_id, result.header.src_conn_id);
    try std.testing.expectEqualSlices(u8, original.token.?, result.header.token.?);
    try std.testing.expectEqual(original.length, result.header.length);
    try std.testing.expectEqual(original.packet_number, result.header.packet_number);
    try std.testing.expectEqual(n, result.len);
}

test "LongHeader Handshake round-trip" {
    const allocator = std.testing.allocator;
    const original = LongHeader{
        .header_type = .HETY_HANDSHAKE,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{ 1, 2, 3, 4 },
        .src_conn_id = &[_]u8{ 5, 6, 7, 8 },
        .token = null,
        .length = 50,
        .packet_number = 2,
    };

    var buf: [64]u8 = undefined;
    const n = try original.toBytes(&buf);

    const result = try LongHeader.fromBytes(buf[0..n], allocator);
    defer result.header.deinit(allocator);

    try std.testing.expectEqual(original.header_type, result.header.header_type);
    try std.testing.expectEqual(original.version, result.header.version);
    try std.testing.expectEqualSlices(u8, original.dest_conn_id, result.header.dest_conn_id);
    try std.testing.expectEqualSlices(u8, original.src_conn_id, result.header.src_conn_id);
    try std.testing.expectEqual(original.length, result.header.length);
    try std.testing.expectEqual(original.packet_number, result.header.packet_number);
    try std.testing.expectEqual(n, result.len);
}

test "ShortHeader round-trip" {
    const allocator = std.testing.allocator;
    const original = ShortHeader{
        .dest_conn_id = &[_]u8{ 0xAA, 0xBB },
        .packet_number = 42,
    };

    var buf: [16]u8 = undefined;
    const n = try original.toBytes(&buf);

    const result = try ShortHeader.fromBytes(buf[0..n], original.dest_conn_id.len, allocator);
    defer result.header.deinit(allocator);

    try std.testing.expectEqualSlices(u8, original.dest_conn_id, result.header.dest_conn_id);
    try std.testing.expectEqual(original.packet_number, result.header.packet_number);
    try std.testing.expectEqual(n, result.len);
}

test "Header.fromBytes dispatch long vs short" {
    const allocator = std.testing.allocator;

    // Long header dispatch
    const lh = LongHeader{
        .header_type = .HETY_INITIAL,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{0xAA},
        .src_conn_id = &[_]u8{0xBB},
        .token = null,
        .length = 10,
        .packet_number = 1,
    };
    var long_buf: [64]u8 = undefined;
    const long_n = try lh.toBytes(&long_buf);

    const long_result = try Header.fromBytes(long_buf[0..long_n], 0, allocator);
    defer long_result.header.deinit(allocator);
    try std.testing.expect(long_result.header == .HETY_INITIAL);

    // Short header dispatch
    const sh = ShortHeader{
        .dest_conn_id = &[_]u8{ 0x01, 0x02 },
        .packet_number = 7,
    };
    var short_buf: [16]u8 = undefined;
    const short_n = try sh.toBytes(&short_buf);

    const short_result = try Header.fromBytes(short_buf[0..short_n], sh.dest_conn_id.len, allocator);
    defer short_result.header.deinit(allocator);
    try std.testing.expect(short_result.header == .HETY_SHORT);
}

test "toBytes BufferTooSmall" {
    const lh = LongHeader{
        .header_type = .HETY_INITIAL,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{ 1, 2, 3, 4 },
        .src_conn_id = &[_]u8{ 5, 6, 7, 8 },
        .token = null,
        .length = 100,
        .packet_number = 1,
    };
    var tiny_buf: [5]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, lh.toBytes(&tiny_buf));

    const sh = ShortHeader{
        .dest_conn_id = &[_]u8{ 0xAA, 0xBB },
        .packet_number = 42,
    };
    var tiny_buf2: [2]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, sh.toBytes(&tiny_buf2));
}

test "fromBytes BufferTooSmall" {
    const allocator = std.testing.allocator;

    const empty: []const u8 = &[_]u8{};
    try std.testing.expectError(error.BufferTooSmall, LongHeader.fromBytes(empty, allocator));
    try std.testing.expectError(error.BufferTooSmall, ShortHeader.fromBytes(empty, 4, allocator));

    // Truncated long header (only first byte)
    const one_byte = [_]u8{0xC0};
    try std.testing.expectError(error.BufferTooSmall, LongHeader.fromBytes(&one_byte, allocator));
}

test "LongHeader multi-byte packet number round-trip" {
    const allocator = std.testing.allocator;
    const original = LongHeader{
        .header_type = .HETY_INITIAL,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{0x01},
        .src_conn_id = &[_]u8{0x02},
        .token = null,
        .length = 200,
        .packet_number = 0x12345678,
    };

    var buf: [64]u8 = undefined;
    const n = try original.toBytes(&buf);

    // packet_number = 0x12345678 requires 4 bytes
    try std.testing.expectEqual(@as(usize, 4), packetNumberLength(0x12345678));
    // first byte should encode pn_len-1 = 3 in bits 1-0: 0xC0 | 0x03 = 0xC3
    try std.testing.expectEqual(@as(u8, 0xC3), buf[0]);
    // packet number bytes at the end
    try std.testing.expectEqual(@as(u8, 0x12), buf[n - 4]);
    try std.testing.expectEqual(@as(u8, 0x34), buf[n - 3]);
    try std.testing.expectEqual(@as(u8, 0x56), buf[n - 2]);
    try std.testing.expectEqual(@as(u8, 0x78), buf[n - 1]);

    const result = try LongHeader.fromBytes(buf[0..n], allocator);
    defer result.header.deinit(allocator);

    try std.testing.expectEqual(original.packet_number, result.header.packet_number);
    try std.testing.expectEqual(original.length, result.header.length);
    try std.testing.expectEqual(n, result.len);
}
