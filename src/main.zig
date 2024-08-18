const std = @import("std");
// Uncomment this block to pass the first stage
const net = std.net;
const print = std.debug.print;

const IP = "127.0.0.1";
const PORT = 4221;
var folder: []const u8 = undefined;

const ServerError = error{
    missingArg,
};

pub fn main() !void {
    var argIter = std.process.args();
    while (argIter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--directory")) {
            if (argIter.next()) |folderArg| {
                folder = folderArg;
            }
            break;
        }
    }

    // Uncomment this block to pass the first stage
    const address = try net.Address.resolveIp(IP, PORT);
    var server = try address.listen(.{
        .reuse_address = true,
    });
    defer server.deinit();

    print("server startet on {s}:{d}\n", .{ IP, PORT });
    while (true) {
        const connection = server.accept() catch {
            print("failes to accept connection", .{});
            continue;
        };

        _ = std.Thread.spawn(.{}, handleConnection, .{connection}) catch |err| {
            print("{s}\n", .{@errorName(err)});
        };
    }
}

fn handleConnection(connection: std.net.Server.Connection) void {
    defer connection.stream.close();

    print("client connected!\n", .{});
    var reqBuf = [_]u8{0} ** 1024;
    var reqStream = std.io.fixedBufferStream(&reqBuf);
    var resBuf = [_]u8{0} ** 1024;
    var resStream = std.io.fixedBufferStream(&resBuf);

    const reqMeta = readRequestMeta(connection.stream.reader(), &reqStream) catch |err| {
        const res = createResponse(&resStream, "400 Bad Request", @errorName(err), "text/plain");
        print("sending response:\n------\n{s}\n-----\n", .{res});
        connection.stream.writeAll(res) catch |writeErr| {
            print("{s}\n", .{@errorName(writeErr)});
        };
        return;
    };

    var res: []const u8 = undefined;
    const target = findtarget(reqMeta);
    if (std.mem.startsWith(u8, target, "/files/")) {
        if (folder.len == 0) {
            print("asset folder not set", .{});
            return;
        }

        const fileName = std.mem.trimLeft(u8, target, "/files/");
        var pathBuf = [_]u8{0} ** 512;
        var pathStream = std.io.fixedBufferStream(&pathBuf);
        const writer = pathStream.writer();
        writer.writeAll(folder) catch {};
        writer.writeAll(fileName) catch {};
        const path = pathStream.getWritten();

        print("opening path: {s}\n", .{path});
        const fileHandle = std.fs.openFileAbsolute(path, .{ .mode = .read_only });

        if (fileHandle) |handle| {
            var fileBuf = [_]u8{0} ** 2048;
            if (handle.readAll(&fileBuf)) |bytesRead| {
                const file = fileBuf[0..bytesRead];
                res = createResponse(&resStream, "200 OK", file, "application/octet-stream");
            } else |err| {
                res = createResponse(&resStream, "500 Interal Server Error", @errorName(err), "text/plain");
            }
        } else |err| {
            print("error opening file: {s}\n", .{@errorName(err)});
            res = createResponse(&resStream, "404 Not Found", "", "text/plain");
        }
    } else if (std.mem.eql(u8, target, "/user-agent")) {
        var iter = std.mem.splitSequence(u8, reqMeta, "\r\n");
        var userAgentHeader: []const u8 = undefined;
        while (iter.next()) |line| {
            const USER_AGENT = "User-Agent: ";
            if (std.ascii.startsWithIgnoreCase(line, USER_AGENT)) userAgentHeader = line[USER_AGENT.len..];
        }
        res = createResponse(&resStream, "200 OK", userAgentHeader, "text/plain");
    } else if (std.mem.startsWith(u8, target, "/echo/")) {
        const string = std.mem.trimLeft(u8, target, "/echo/");
        print("recieved echo string: {s}\n", .{string});
        res = createResponse(&resStream, "200 OK", string, "text/plain");
    } else if (std.mem.eql(u8, target, "/")) {
        res = createResponse(&resStream, "200 OK", "", "text/plain");
    } else {
        res = createResponse(&resStream, "404 Not Found", "", "text/plain");
    }

    print("sending response:\n------\n{s}\n-----\n", .{res});
    connection.stream.writeAll(res) catch |err| {
        print("{s}\n", .{@errorName(err)});
    };
    print("closing connection!\n", .{});
}

fn createResponse(stream: *std.io.FixedBufferStream([]u8), status: []const u8, body: []const u8, contentType: []const u8) []const u8 {
    const writer = stream.writer();

    writer.print("HTTP/1.1 {s}\r\n", .{status}) catch {};
    writer.print("Content-Type: {s}\r\n", .{contentType}) catch {};
    writer.print("Content-Length: {d}\r\n", .{body.len}) catch {};
    writer.print("\r\n", .{}) catch {};
    writer.print("{s}", .{body}) catch {};

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
