const std = @import("std");
// Uncomment this block to pass the first stage
const net = std.net;
const print = std.debug.print;

const IP = "127.0.0.1";
const PORT = 4221;

pub fn main() !void {

    // Uncomment this block to pass the first stage
    const address = try net.Address.resolveIp(IP, PORT);
    var server = try address.listen(.{
        .reuse_address = true,
    });
    defer server.deinit();

    print("server startet on {s}:{d}\n", .{ IP, PORT });
    while (true) {
        var connection = server.accept() catch {
            print("failes to accept connection", .{});
            continue;
        };

        try handleConnection(&connection);
    }
}

fn handleConnection(connection: *std.net.Server.Connection) !void {
    print("client connected!\n", .{});
    var reqBuf = [_]u8{0} ** 1024;
    var reqStream = std.io.fixedBufferStream(&reqBuf);
    var resBuf = [_]u8{0} ** 1024;
    var resStream = std.io.fixedBufferStream(&resBuf);

    const reqMeta = readRequestMeta(connection.stream.reader(), &reqStream) catch |err| {
        const res = try createResponse(&resStream, "400 Bad Request", @errorName(err));
        print("sending response:\n------\n{s}\n-----\n", .{res});
        try connection.stream.writeAll(res);
        return;
    };

    var res: []const u8 = undefined;
    const target = findtarget(reqMeta);
    if (std.mem.eql(u8, target, "/user-agent")) {
        var iter = std.mem.splitSequence(u8, reqMeta, "\r\n");
        var userAgentHeader: []const u8 = undefined;
        while (iter.next()) |line| {
            if (std.ascii.startsWithIgnoreCase(line, "user-agent: ")) userAgentHeader = line[12..];
        }
        res = try createResponse(&resStream, "200 OK", userAgentHeader);
    } else if (std.mem.startsWith(u8, target, "/echo/")) {
        const string = std.mem.trimLeft(u8, target, "/echo/");
        res = try createResponse(&resStream, "200 OK", string);
    } else if (std.mem.eql(u8, target, "/")) {
        res = try createResponse(&resStream, "200 OK", "");
        print("sending response:\n------\n{s}\n-----\n", .{res});
    } else {
        res = try createResponse(&resStream, "404 Not Found", "");
        print("sending response:\n------\n{s}\n-----\n", .{res});
    }

    try connection.stream.writeAll(res);
    print("closing connection!\n", .{});
    connection.stream.close();
}

fn createResponse(stream: *std.io.FixedBufferStream([]u8), status: []const u8, body: []const u8) ![]const u8 {
    const writer = stream.writer();

    try writer.print("HTTP/1.1 {s}\r\n", .{status});
    try writer.print("Connection: close\r\n", .{});
    try writer.print("Content-Type: text/plain\r\n", .{});
    try writer.print("Content-Length: {d}\r\n", .{body.len});
    try writer.print("\r\n", .{});
    try writer.print("{s}", .{body});

    return stream.getWritten();
}

fn readRequestMeta(streamReader: std.net.Stream.Reader, reqStream: *std.io.FixedBufferStream([]u8)) ![]u8 {
    const writer = reqStream.writer();
    var last: u8 = 0;
    while (true) {
        const byte = try streamReader.readByte();
        try writer.writeByte(byte);

        if (byte == '\r' and last == '\n') {
            break;
        }

        last = byte;
    }

    return reqStream.getWritten();
}

fn findtarget(string: []const u8) []const u8 {
    var splitIter = std.mem.splitScalar(u8, string, ' ');
    _ = splitIter.next();

    return splitIter.next() orelse "";
}
