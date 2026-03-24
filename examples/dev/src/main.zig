//! QUIC Debug Sniffer
//!
//! Binds a blocking UDP socket and prints a hex dump + parsed QUIC header
//! for every datagram received. Useful for debugging raw QUIC packet structure.
//!
//! Usage:
//!   zig build run              # listens on 0.0.0.0:6969
//!   zig build run -- --port 9000
//!   zig build run -- --host 127.0.0.1 --port 9000
//!
//! Send a test Initial packet:
//!   printf '\xc0\x00\x00\x00\x01\x04\xde\xad\xbe\xef\x04\xca\xfe\xba\xbe\x00\x40\x64\x01' \
//!     | nc -u 127.0.0.1 6969

const std = @import("std");
const net = std.net;
const posix = std.posix; // UDP has no cross-platform stdlib abstraction in Zig

const quic_zig = @import("quic_zig");
const Header = quic_zig.core.Header;
const LongHeader = quic_zig.core.LongHeader;
const parseHeader = quic_zig.core.parseHeader;

const p = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var port: u16 = 6969;
    var host: []const u8 = "0.0.0.0";

    var idx: usize = 1;
    while (idx < args.len) : (idx += 1) {
        if (std.mem.eql(u8, args[idx], "--port") and idx + 1 < args.len) {
            idx += 1;
            port = try std.fmt.parseInt(u16, args[idx], 10);
        } else if (std.mem.eql(u8, args[idx], "--host") and idx + 1 < args.len) {
            idx += 1;
            host = args[idx];
        }
    }

    // Blocking UDP socket (no SOCK_NONBLOCK — recvfrom blocks until data arrives)
    const fd = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    defer posix.close(fd);

    const addr = try net.Address.parseIp4(host, port);
    try posix.bind(fd, &addr.any, addr.getOsSockLen());

    p("quic-sniffer listening on {s}:{d}\n\n", .{ host, port });

    var pkt_buf: [65535]u8 = undefined;
    var count: u64 = 0;

    while (true) {
        var src_storage: posix.sockaddr.storage = undefined;
        var src_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);

        const n = posix.recvfrom(fd, &pkt_buf, 0, @ptrCast(&src_storage), &src_len) catch |err| {
            p("[recv error: {}]\n", .{err});
            continue;
        };

        count += 1;
        const pkt = pkt_buf[0..n];
        const from = net.Address.initPosix(@ptrCast(@alignCast(&src_storage)));

        p("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        p("  Packet #{d}   from {any}   {d} bytes\n", .{ count, from, pkt.len });
        p("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

        if (pkt.len == 0) {
            p("  [empty datagram]\n\n", .{});
            continue;
        }

        hexDump(pkt);
        p("\n", .{});
        printFirstByte(pkt[0]);
        p("\n", .{});

        const is_short = pkt[0] & 0x80 == 0;
        if (is_short) {
            p("[QUIC Header — Short (trying common conn_id_len values)]\n", .{});
            const tries = [_]usize{ 0, 4, 8, 16, 20 };
            var parsed = false;
            for (tries) |cil| {
                const r = parseHeader(pkt, cil, allocator) catch continue;
                defer r.header.deinit(allocator);
                p("  (matched conn_id_len={d})\n", .{cil});
                printHeader(r.header);
                p("  payload:  {d} bytes", .{r.payload.len});
                inlineHex(r.payload, 16);
                p("\n", .{});
                parsed = true;
                break;
            }
            if (!parsed) p("  could not parse with common conn_id_len values\n", .{});
        } else {
            p("[QUIC Header — Long]\n", .{});
            const r = parseHeader(pkt, 0, allocator) catch |err| {
                p("  parse error: {}\n\n", .{err});
                continue;
            };
            defer r.header.deinit(allocator);
            printHeader(r.header);
            p("  payload:  {d} bytes", .{r.payload.len});
            inlineHex(r.payload, 32);
            p("\n", .{});
        }

        p("\n", .{});
    }
}

fn printFirstByte(b: u8) void {
    p("[First Byte 0x{x:0>2}]\n", .{b});
    p("  bit 7 (header form): {s}\n", .{
        if (b & 0x80 != 0) "1 → long header" else "0 → short header",
    });
    p("  bit 6 (fixed bit):   {d}\n", .{(b >> 6) & 1});
    if (b & 0x80 != 0) {
        const pt = (b >> 4) & 0x03;
        const name: []const u8 = switch (pt) {
            0 => "Initial",
            1 => "0-RTT",
            2 => "Handshake",
            3 => "Retry",
            else => "unknown",
        };
        p("  bits 5-4 (pkt type): {d} → {s}\n", .{ pt, name });
    } else {
        p("  bit 5 (spin):        {d}\n", .{(b >> 5) & 1});
        p("  bit 2 (key phase):   {d}\n", .{(b >> 2) & 1});
    }
    p("  bits 1-0 (pn_len-1): {d} → packet number is {d} byte(s)\n", .{
        b & 0x03, (b & 0x03) + 1,
    });
}

fn printHeader(h: Header) void {
    switch (h) {
        .HETY_INITIAL => |lh| printLongHeader(lh, "Initial"),
        .HETY_HANDSHAKE => |lh| printLongHeader(lh, "Handshake"),
        .HETY_0RTT => |lh| printLongHeader(lh, "0-RTT"),
        .HETY_SHORT => |sh| {
            p("  type:     Short (1-RTT)\n", .{});
            p("  dcid:     ", .{});
            printBytes(sh.dest_conn_id);
            p("\n", .{});
            p("  pkt_num:  {d} (0x{x})\n", .{ sh.packet_number, sh.packet_number });
        },
        .HETY_VERNEG => p("  type:     Version Negotiation\n", .{}),
        .HETY_RETRY => p("  type:     Retry\n", .{}),
    }
}

fn printLongHeader(lh: LongHeader, name: []const u8) void {
    p("  type:     {s}\n", .{name});
    p("  version:  0x{x:0>8}", .{lh.version});
    if (lh.version == 0x00000001) p("  (QUIC v1)", .{});
    if (lh.version == 0x00000000) p("  (Version Negotiation)", .{});
    p("\n", .{});
    p("  dcid:     ", .{});
    printBytes(lh.dest_conn_id);
    p("  ({d} bytes)\n", .{lh.dest_conn_id.len});
    p("  scid:     ", .{});
    printBytes(lh.src_conn_id);
    p("  ({d} bytes)\n", .{lh.src_conn_id.len});
    if (lh.token) |tok| {
        p("  token:    ", .{});
        printBytes(tok);
        p("  ({d} bytes)\n", .{tok.len});
    }
    p("  length:   {d}\n", .{lh.length});
    p("  pkt_num:  {d} (0x{x})\n", .{ lh.packet_number, lh.packet_number });
}

fn hexDump(data: []const u8) void {
    var line: [128]u8 = undefined;
    var offset: usize = 0;
    while (offset < data.len) : (offset += 16) {
        const end = @min(offset + 16, data.len);
        const chunk = data[offset..end];
        var pos: usize = 0;
        pos += (std.fmt.bufPrint(line[pos..], "  {x:0>4}  ", .{offset}) catch return).len;
        for (chunk, 0..) |b, j| {
            if (j == 8) { line[pos] = ' '; pos += 1; }
            pos += (std.fmt.bufPrint(line[pos..], "{x:0>2} ", .{b}) catch return).len;
        }
        if (chunk.len < 16) {
            const missing = 16 - chunk.len;
            for (0..missing) |j| {
                if (j + chunk.len == 8) { line[pos] = ' '; pos += 1; }
                line[pos] = ' '; line[pos + 1] = ' '; line[pos + 2] = ' '; pos += 3;
            }
        }
        line[pos] = ' '; line[pos + 1] = '|'; pos += 2;
        for (chunk) |b| { line[pos] = if (std.ascii.isPrint(b)) b else '.'; pos += 1; }
        line[pos] = '|'; line[pos + 1] = '\n'; pos += 2;
        p("{s}", .{line[0..pos]});
    }
}

fn inlineHex(data: []const u8, max: usize) void {
    if (data.len == 0) return;
    p("  [", .{});
    const show = @min(data.len, max);
    for (data[0..show]) |b| p("{x:0>2} ", .{b});
    if (data.len > max) p("...", .{});
    p("]", .{});
}

fn printBytes(data: []const u8) void {
    for (data) |b| p("{x:0>2}", .{b});
    if (data.len > 0) p(" ", .{});
}
