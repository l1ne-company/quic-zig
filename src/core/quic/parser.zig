const std = @import("std");
const header_module = @import("header.zig");
const Header = header_module.Header;

pub const ParseResult = struct {
    header: Header,
    header_len: usize,
    payload: []const u8,
};

/// Parse a QUIC header from a raw packet buffer.
/// conn_id_len is required for short (1-RTT) headers where the connection ID
/// length is not encoded on the wire and must be known from connection state.
/// The caller owns the allocated memory in the returned header; call header.deinit(allocator).
pub fn parseHeader(buf: []const u8, conn_id_len: usize, allocator: std.mem.Allocator) !ParseResult {
    const result = try Header.fromBytes(buf, conn_id_len, allocator);
    return ParseResult{
        .header = result.header,
        .header_len = result.len,
        .payload = buf[result.len..],
    };
}

test "parseHeader Initial with payload" {
    const allocator = std.testing.allocator;

    const lh = header_module.LongHeader{
        .header_type = .HETY_INITIAL,
        .version = 0x00000001,
        .dest_conn_id = &[_]u8{ 1, 2, 3, 4 },
        .src_conn_id = &[_]u8{ 5, 6, 7, 8 },
        .token = null,
        .length = 5, // 5-byte payload follows the header
        .packet_number = 1,
    };

    // Serialize header into a packet buffer with 5 trailing payload bytes
    var packet: [64]u8 = undefined;
    const header_n = try lh.toBytes(&packet);
    const payload_bytes = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF, 0xFF };
    @memcpy(packet[header_n .. header_n + 5], &payload_bytes);
    const total = header_n + 5;

    const pr = try parseHeader(packet[0..total], 0, allocator);
    defer pr.header.deinit(allocator);

    try std.testing.expect(pr.header == .HETY_INITIAL);
    try std.testing.expectEqual(header_n, pr.header_len);
    try std.testing.expectEqualSlices(u8, &payload_bytes, pr.payload);

    const inner = pr.header.HETY_INITIAL;
    try std.testing.expectEqual(@as(u32, 0x00000001), inner.version);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4 }, inner.dest_conn_id);
    try std.testing.expectEqual(@as(u32, 1), inner.packet_number);
}

test "parseHeader Short with payload" {
    const allocator = std.testing.allocator;

    const sh = header_module.ShortHeader{
        .dest_conn_id = &[_]u8{ 0xAA, 0xBB },
        .packet_number = 42,
    };

    var packet: [32]u8 = undefined;
    const header_n = try sh.toBytes(&packet);
    const payload_bytes = [_]u8{ 0x01, 0x02, 0x03 };
    @memcpy(packet[header_n .. header_n + 3], &payload_bytes);
    const total = header_n + 3;

    const pr = try parseHeader(packet[0..total], sh.dest_conn_id.len, allocator);
    defer pr.header.deinit(allocator);

    try std.testing.expect(pr.header == .HETY_SHORT);
    try std.testing.expectEqual(header_n, pr.header_len);
    try std.testing.expectEqualSlices(u8, &payload_bytes, pr.payload);

    const inner = pr.header.HETY_SHORT;
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xAA, 0xBB }, inner.dest_conn_id);
    try std.testing.expectEqual(@as(u32, 42), inner.packet_number);
}
