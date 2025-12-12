const std = @import("std");
const quic_zig = @import("quic_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try quic_zig.bufferedPrint();
    // Test UDP socket
    std.debug.print("\nTesting UDP Socket...\n", .{});
    try testUdp(allocator);
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
    std.debug.print("Receiver bound successfully\n", .{});

    // Get receiver's address
    var addr: std.posix.sockaddr.storage = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.storage);
    try std.posix.getsockname(receiver.fd, @ptrCast(&addr), &addr_len);
    const receiver_addr = std.net.Address.initPosix(@ptrCast(@alignCast(&addr)));

    // Send message
    const message = "poggers!";
    const bytes_sent = try sender.send(message, receiver_addr);
    std.debug.print("Sent {d} bytes: {s}\n", .{ bytes_sent, message });
    var buffer: [1024]u8 = undefined;
    const result = receiver.recv(&buffer) catch |err| {
        if (err == error.WouldBlock) {
            std.debug.print("No message received (WouldBlock)\n", .{});
            return;
        }
        return err;
    };
    std.debug.print("Received {d} bytes: {s}\n", .{ result.bytes, buffer[0..result.bytes] });
}
