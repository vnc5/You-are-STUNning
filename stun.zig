const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

pub fn main() !void {
    const args = std.os.argv;
    var host: [:0]const u8 = "::";
    if (args.len > 1) {
        host = std.mem.span(args[1]);
    }
    var port: u16 = 3478;
    if (args.len > 2) {
        port = try std.fmt.parseInt(u16, std.mem.span(args[2]), 10);
    }
    var threads = try std.Thread.getCpuCount();
    if (args.len > 3) {
        threads = try std.fmt.parseInt(usize, std.mem.span(args[3]), 10);
    }
    var address = try std.net.Address.parseIp(host, port);
    for (1..threads) |_| {
        _ = try std.Thread.spawn(.{}, listen, .{ &address, false });
    }
    try listen(&address, true);
}

fn listen(address: *std.net.Address, isMain: bool) !void {
    const sockfd = try posix.socket(address.any.family, posix.SOCK.DGRAM | posix.SOCK.CLOEXEC, posix.IPPROTO.UDP);
    errdefer posix.close(sockfd);
    if (builtin.os.tag == .windows) {
        // Windows apparently has REUSEADDR only which apparently also completely takes over the port and therefore no load balancing whatsoever. Last one wins?
        try posix.setsockopt(sockfd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        // Zig: posix.SOL.IPV6 is missing for Windows: std.c.windows.SOL.IPV6
        try posix.setsockopt(sockfd, std.os.linux.IPPROTO.IPV6, std.os.windows.ws2_32.IPV6_V6ONLY, &std.mem.toBytes(@as(c_int, 0)));
    } else if (builtin.os.tag == .linux) {
        try posix.setsockopt(sockfd, posix.SOL.SOCKET, posix.SO.REUSEPORT, &std.mem.toBytes(@as(c_int, 1)));
    }
    var socklen = address.getOsSockLen();
    var listen_address: std.net.Address = undefined;
    try posix.bind(sockfd, &address.any, socklen);
    try posix.getsockname(sockfd, &listen_address.any, &socklen);

    if (isMain) {
        try std.io.getStdOut().writer().print("Listening on UDP {}\n", .{listen_address});
    }

    try recv(sockfd);
}

fn recv(sockfd: posix.socket_t) !void {
    const is_ipv4 = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff };
    const binding_req = [_]u8{ 0b00_00000_0, 0b000_0_0001 };
    var xor_mapped_addr = [_]u8{ 0x00, 0x20, 0x00, 0x08, 0x00, 0x01 };

    var addr: std.net.Ip6Address = undefined;
    var addr_len = addr.getOsSockLen();
    var buf = [_]u8{0} ** 1500;
    while (true) {
        const len = posix.recvfrom(sockfd, &buf, 0, @ptrCast(&addr), &addr_len) catch |err| {
            var fbs_buf: [100]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&fbs_buf);
            try addr.format("", .{}, fbs.writer());
            std.log.err("recvfrom failed with error: {s}. ip {s}", .{
                @errorName(err),
                fbs.getWritten(),
            });
            continue;
        };
        if (len < 20) continue;
        if (addr.sa.port == 0) continue;
        if (!std.mem.eql(u8, buf[0..2], &binding_req)) continue;
        buf[0] = 0b00_00000_1; // binding success response
        var ip_offset: u8 = 0; // ipv4 is stored at the end in addr.sa.addr
        if (std.mem.eql(u8, addr.sa.addr[0..12], &is_ipv4)) {
            buf[3] = 12; // length
            xor_mapped_addr[3] = 8; // ipv4 length
            xor_mapped_addr[5] = 1; // ipv4
            ip_offset = 12;
        } else {
            buf[3] = 24; // length
            xor_mapped_addr[3] = 20; // ipv6 length
            xor_mapped_addr[5] = 2; // ipv6
        }
        std.mem.copyForwards(u8, buf[20..], &xor_mapped_addr);
        std.mem.writeInt(u16, buf[26..28], addr.sa.port ^ 0x1221, .little); // swap magic byte order because sa.port big endian
        for (0..(16 - ip_offset)) |i| {
            buf[28 + i] = addr.sa.addr[ip_offset + i] ^ buf[4 + i]; // xor address with transaction id (incl magic cookie)
        }
        _ = posix.sendto(sockfd, buf[0..(28 + (16 - ip_offset))], 0, @ptrCast(&addr), addr_len) catch |err| {
            var fbs_buf: [100]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&fbs_buf);
            try addr.format("", .{}, fbs.writer());
            std.log.err("sendto failed with error: {s}. ip {s}", .{
                @errorName(err),
                fbs.getWritten(),
            });
            continue;
        };
    }
}
