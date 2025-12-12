const std = @import("std");
const posix = std.posix;
const net = std.net;

pub const RecvResult = struct {
    bytes: usize,
    from: net.Address,
};

pub const UdpSocket = struct {
    fd: posix.socket_t,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !UdpSocket {
        const fd = posix.socket(posix.AF.INET, posix.SOCK.DGRAM | posix.SOCK.NONBLOCK, posix.IPPROTO.UDP) catch {
            return error.SocketCreationFailed;
        };
        errdefer posix.close(fd);

        return UdpSocket{
            .fd = fd,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UdpSocket) void {
        posix.close(self.fd);
    }

    pub fn bind(self: *UdpSocket, address: []const u8, port: u16) !void {
        const addr = net.Address.parseIp4(address, port) catch {
            return error.InvalidAddress;
        };
        posix.bind(self.fd, &addr.any, addr.getOsSockLen()) catch {
            return error.BindFailed;
        };
    }

    pub fn send(self: *UdpSocket, data: []const u8, dest_addr: net.Address) !usize {
        const bytes_sent = posix.sendto(
            self.fd,
            data,
            0,
            &dest_addr.any,
            dest_addr.getOsSockLen(),
        ) catch |err| {
            return switch (err) {
                error.WouldBlock => error.WouldBlock,
                else => error.SendFailed,
            };
        };
        return bytes_sent;
    }

    pub fn recv(self: *UdpSocket, buffer: []u8) !RecvResult {
        var src_addr: posix.sockaddr.storage = undefined;
        var src_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);

        const bytes_received = posix.recvfrom(
            self.fd,
            buffer,
            0,
            @ptrCast(&src_addr),
            &src_addr_len,
        ) catch |err| {
            return switch (err) {
                error.WouldBlock => error.WouldBlock,
                else => error.ReceiveFailed,
            };
        };

        // Convert sockaddr to std.net.Address
        const from_addr = net.Address.initPosix(@ptrCast(@alignCast(&src_addr)));

        return RecvResult{
            .bytes = bytes_received,
            .from = from_addr,
        };
    }
};

test "UdpSocket.init and deinit" {
    const allocator = std.testing.allocator;
    var socket = try UdpSocket.init(allocator);
    defer socket.deinit();
    try std.testing.expect(socket.fd > 0);
}

test "UdpSocket.bind to address" {
    const allocator = std.testing.allocator;
    var socket = try UdpSocket.init(allocator);
    defer socket.deinit();
    try socket.bind("127.0.0.1", 0);
}

test "UdpSocket.bind to specific port" {
    const allocator = std.testing.allocator;
    var socket = try UdpSocket.init(allocator);
    defer socket.deinit();
    const port: u16 = 9999;
    socket.bind("127.0.0.1", port) catch |err| {
        if (err == error.BindFailed) return;
        return err;
    };
}

test "UdpSocket.send and recv" {
    const allocator = std.testing.allocator;
    var sender = try UdpSocket.init(allocator);
    defer sender.deinit();
    var receiver = try UdpSocket.init(allocator);
    defer receiver.deinit();
    try receiver.bind("127.0.0.1", 0);
    var addr: posix.sockaddr.storage = undefined;
    var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
    try posix.getsockname(receiver.fd, @ptrCast(&addr), &addr_len);
    const receiver_addr = net.Address.initPosix(@ptrCast(@alignCast(&addr)));
    const message = "Hello, UDP!";
    const bytes_sent = try sender.send(message, receiver_addr);
    try std.testing.expectEqual(message.len, bytes_sent);
    var buffer: [1024]u8 = undefined;
    const result = try receiver.recv(&buffer);
    try std.testing.expectEqual(message.len, result.bytes);
    try std.testing.expectEqualSlices(u8, message, buffer[0..result.bytes]);
}

test "UdpSocket.recv returns WouldBlock on empty socket" {
    const allocator = std.testing.allocator;
    var socket = try UdpSocket.init(allocator);
    defer socket.deinit();
    try socket.bind("127.0.0.1", 0);
    var buffer: [1024]u8 = undefined;
    const result = socket.recv(&buffer);
    try std.testing.expectError(error.WouldBlock, result);
}

test "UdpSocket.bind invalid address" {
    const allocator = std.testing.allocator;
    var socket = try UdpSocket.init(allocator);
    defer socket.deinit();
    const result = socket.bind("999.999.999.999", 8080);
    try std.testing.expectError(error.InvalidAddress, result);
}

test "UdpSocket.send and recv multiple messages" {
    const allocator = std.testing.allocator;
    var sender = try UdpSocket.init(allocator);
    defer sender.deinit();
    var receiver = try UdpSocket.init(allocator);
    defer receiver.deinit();
    try receiver.bind("127.0.0.1", 0);
    var addr: posix.sockaddr.storage = undefined;
    var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
    try posix.getsockname(receiver.fd, @ptrCast(&addr), &addr_len);
    const receiver_addr = net.Address.initPosix(@ptrCast(@alignCast(&addr)));
    const messages = [_][]const u8{ "First", "Second", "Third" };
    for (messages) |msg| {
        _ = try sender.send(msg, receiver_addr);
    }
    var buffer: [1024]u8 = undefined;
    for (messages) |expected_msg| {
        const result = try receiver.recv(&buffer);
        try std.testing.expectEqual(expected_msg.len, result.bytes);
        try std.testing.expectEqualSlices(u8, expected_msg, buffer[0..result.bytes]);
    }
}

test "UdpSocket.recv verifies sender address" {
    const allocator = std.testing.allocator;
    var sender = try UdpSocket.init(allocator);
    defer sender.deinit();
    try sender.bind("127.0.0.1", 0);
    var sender_addr_storage: posix.sockaddr.storage = undefined;
    var sender_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
    try posix.getsockname(sender.fd, @ptrCast(&sender_addr_storage), &sender_addr_len);
    const actual_sender_addr = net.Address.initPosix(@ptrCast(@alignCast(&sender_addr_storage)));
    var receiver = try UdpSocket.init(allocator);
    defer receiver.deinit();
    try receiver.bind("127.0.0.1", 0);
    var receiver_addr_storage: posix.sockaddr.storage = undefined;
    var receiver_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);
    try posix.getsockname(receiver.fd, @ptrCast(&receiver_addr_storage), &receiver_addr_len);
    const receiver_addr = net.Address.initPosix(@ptrCast(@alignCast(&receiver_addr_storage)));
    const message = "Address test";
    _ = try sender.send(message, receiver_addr);
    var buffer: [1024]u8 = undefined;
    const result = try receiver.recv(&buffer);
    try std.testing.expectEqual(actual_sender_addr.getPort(), result.from.getPort());
}

test "UdpSocket.multiple sockets can coexist" {
    const allocator = std.testing.allocator;
    var socket1 = try UdpSocket.init(allocator);
    defer socket1.deinit();
    var socket2 = try UdpSocket.init(allocator);
    defer socket2.deinit();
    var socket3 = try UdpSocket.init(allocator);
    defer socket3.deinit();
    try socket1.bind("127.0.0.1", 0);
    try socket2.bind("127.0.0.1", 0);
    try socket3.bind("127.0.0.1", 0);
    try std.testing.expect(socket1.fd != socket2.fd);
    try std.testing.expect(socket2.fd != socket3.fd);
    try std.testing.expect(socket1.fd != socket3.fd);
}
