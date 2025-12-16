const std = @import("std");
const quic_zig = @import("quic_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testUdp(allocator);
    try testFrameAndPacket(allocator);
}

pub fn testUdp(allocator: std.mem.Allocator) !void {
    const UdpSocket = quic_zig.core.UdpSocket;

    // Create sender and receiver sockets
    var sender = try UdpSocket.init(allocator);
    defer sender.deinit();

    var receiver = try UdpSocket.init(allocator);
    defer receiver.deinit();

    // Bind receiver to localhost with dynamic port
    try receiver.bind("127.0.0.1", 0);
    std.debug.print("   ✓ Receiver bound successfully\n", .{});

    // Get receiver's address
    var addr: std.posix.sockaddr.storage = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.storage);
    try std.posix.getsockname(receiver.fd, @ptrCast(&addr), &addr_len);
    const receiver_addr = std.net.Address.initPosix(@ptrCast(@alignCast(&addr)));

    // Send message
    const message = "poggers!";
    const bytes_sent = try sender.send(message, receiver_addr);
    std.debug.print("   ✓ Sent {d} bytes: {s}\n", .{ bytes_sent, message });
    var buffer: [1024]u8 = undefined;
    const result = receiver.recv(&buffer) catch |err| {
        if (err == error.WouldBlock) {
            std.debug.print("   ✓ No message received (WouldBlock)\n", .{});
            return;
        }
        return err;
    };
    std.debug.print("   ✓ Received {d} bytes: {s}\n", .{ result.bytes, buffer[0..result.bytes] });
}

pub fn testFrameAndPacket(allocator: std.mem.Allocator) !void {
    // Create PING frame
    const ping_frame = quic_zig.core.Frame{ .PING = quic_zig.core.PingFrame{} };
    std.debug.print("   ✓ Created PING frame (size: {d} byte)\n", .{ping_frame.size()});

    // Create PADDING frame
    const padding_frame = quic_zig.core.Frame{
        .PADDING = quic_zig.core.PaddingFrame{ .count = 50 },
    };
    std.debug.print("   ✓ Created PADDING frame (size: {d} bytes)\n", .{padding_frame.size()});

    // Create packet header
    const header = quic_zig.core.Header{
        .HETY_SHORT = quic_zig.core.ShortHeader{
            .dest_conn_id = &[_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 },
            .packet_number = 1,
        },
    };
    std.debug.print("   ✓ Created SHORT header\n", .{});

    // Create packet with frames
    var packet = quic_zig.core.Packet.init(allocator, header);
    defer packet.deinit();

    try packet.addFrame(ping_frame);
    std.debug.print("   ✓ Added PING frame to packet\n", .{});

    try packet.addFrame(padding_frame);
    std.debug.print("   ✓ Added PADDING frame to packet\n", .{});

    std.debug.print("   ✓ Packet contains {d} frames\n", .{packet.frames_count});
    std.debug.print("   ✓ Total packet payload size: {d} bytes\n", .{packet.size()});

    // Demonstrate VarInt encoding
    std.debug.print("\n3. Testing VarInt Encoding...\n", .{});
    var varint_buf: [8]u8 = undefined;

    const test_values = [_]u64{ 25, 100, 1000, 16383, 16384, 1000000, 1073741824 };
    for (test_values) |value| {
        const len = try quic_zig.utils.VarInt.encode(value, &varint_buf);
        const result = try quic_zig.utils.VarInt.decode(varint_buf[0..len]);
        std.debug.print("   ✓ VarInt {d}: {d}-byte encoding -> {d}\n", .{ value, len, result.value });
    }
}
