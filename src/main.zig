const std = @import("std");
// Uncomment this block to pass the first stage
const net = std.net;
const print = std.debug.print;
const http = @import("./http.zig");
const Router = @import("./router.zig");

const IP = "127.0.0.1";
const PORT = 4221;
var assets: []const u8 = undefined;

pub fn main() !void {
    getAssetFolder();

    const address = try net.Address.resolveIp(IP, PORT);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    print("server startet on {s}:{d}\n", .{ IP, PORT });
    while (true) {
        const connection = server.accept() catch |err| {
            print("failed to accept connection: {s}\n", .{@errorName(err)});
            continue;
        };

        const thread = std.Thread.spawn(.{}, handleConnection, .{connection}) catch |err| {
            print("failed to spawn thread: {s}\n", .{@errorName(err)});
            connection.stream.close();
            continue;
        };
        thread.detach();
    }
}

fn getAssetFolder() void {
    var argIter = std.process.args();
    while (argIter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--directory")) {
            if (argIter.next()) |path| {
                assets = path;
            }
            break;
        }
    }
}

fn handleConnection(connection: std.net.Server.Connection) void {
    print("client connected!\n", .{});

    var buffer: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var router = Router.Router.init(allocator);
    router.addRoute(Router.Route{ .match = &matchFilesGet, .handler = &handleFilesGet });
    router.addRoute(Router.Route{ .match = &matchFilesPost, .handler = &handleFilesPost });
    router.addRoute(Router.Route{ .match = &matchUserAgent, .handler = &handleUserAgent });
    router.addRoute(Router.Route{ .match = &matchEcho, .handler = &handleEcho });
    router.addRoute(Router.Route{ .match = &matchRoot, .handler = &handleHome });

    var res = http.Result.init(allocator);
    if (http.Request.parse(allocator, connection.stream.reader())) |val| {
        var req = val;
        print("request:\n{}\n", .{req});

        res.header.add("Connection", "close");
        router.handle(&req, &res);
    } else |err| {
        res.status = http.Status.BAD_REQUEST;
        res.writeBody(@errorName(err));
    }

    print("sending response:\n------\n{}\n-----\n", .{res});
    connection.stream.writer().print("{}", .{res}) catch |err| {
        print("failed to send response: {s}", .{@errorName(err)});
    };
    print("closing connection!\n", .{});
}

fn matchRoot(req: *http.Request) bool {
    return std.mem.eql(u8, req.target, "/");
}

fn handleHome(_: *http.Request, _: *http.Result) void {}

fn matchEcho(req: *http.Request) bool {
    return std.mem.startsWith(u8, req.target, "/echo/");
}

fn handleEcho(req: *http.Request, res: *http.Result) void {
    const echo = req.target[6..];
    print("recieved echo string: {s}\n", .{echo});

    if (req.header.findHeader(http.Header.AcceptEncoding)) |value| {
        if (std.mem.count(u8, value, "gzip") > 0) {
            res.header.add(http.Header.ContentEncoding, "gzip");
        }
    }

    res.writeBody(echo);
}

fn matchUserAgent(req: *http.Request) bool {
    return std.mem.eql(u8, req.target, "/user-agent");
}

fn handleUserAgent(req: *http.Request, res: *http.Result) void {
    const userAgentHeader = req.header.findHeader(http.Header.UserAgent) orelse "";
    res.writeBody(userAgentHeader);
}

fn matchFilesGet(req: *http.Request) bool {
    return std.mem.startsWith(u8, req.target, "/files/") and std.mem.eql(u8, req.method, "GET");
}

fn handleFilesGet(req: *http.Request, res: *http.Result) void {
    if (assets.len == 0) {
        print("asset folder not set", .{});
        return;
    }

    var pathBuf: [128]u8 = undefined;
    const path = std.fmt.bufPrint(&pathBuf, "{s}{s}", .{ assets, req.target[7..] }) catch "print err";
    print("working with path: {s}\n", .{path});

    const fileHandle = std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    if (fileHandle) |handle| {
        defer handle.close();
        var fileBuf: [2048]u8 = undefined;

        if (handle.readAll(&fileBuf)) |bytesRead| {
            const file = fileBuf[0..bytesRead];
            res.header.contentType("application/octet-stream");
            res.writeBody(file);
        } else |err| {
            res.status = http.Status.NOT_FOUND;
            res.writeBody(@errorName(err));
        }
    } else |err| {
        print("error opening file: {s}\n", .{@errorName(err)});
        res.status = http.Status.NOT_FOUND;
        res.writeBody(@errorName(err));
    }
}

fn matchFilesPost(req: *http.Request) bool {
    return std.mem.startsWith(u8, req.target, "/files/") and std.mem.eql(u8, req.method, "POST");
}

fn handleFilesPost(req: *http.Request, res: *http.Result) void {
    if (assets.len == 0) {
        print("asset folder not set", .{});
        return;
    }

    var pathBuf: [128]u8 = undefined;
    const path = std.fmt.bufPrint(&pathBuf, "{s}{s}", .{ assets, req.target[7..] }) catch "print err";
    print("working with path: {s}\n", .{path});

    const file = std.fs.createFileAbsolute(path, .{}) catch |err| {
        res.status = http.Status.SERVER_ERROR;
        res.writeBody(@errorName(err));
        return;
    };
    defer file.close();

    file.writeAll(req.body) catch |err| {
        res.status = http.Status.SERVER_ERROR;
        res.writeBody(@errorName(err));
        return;
    };

    res.status = http.Status.CREATED;
}
