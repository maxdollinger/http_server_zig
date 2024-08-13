const std = @import("std");
// Uncomment this block to pass the first stage
const net = std.net;
const print = std.debug.print;

const http = @import("./http/http.zig");

pub fn main() !void {

    // You can use print statements as follows for debugging, they'll be visible when running tests.
    print("Logs from your program will appear here!\n", .{});

    // Uncomment this block to pass the first stage
    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var server = try address.listen(.{
        .reuse_address = true,
    });
    defer server.deinit();

    var connection = try server.accept();
    try handleConnection(&connection);
}

fn handleConnection(connection: *std.net.Server.Connection) !void {
    print("client connected!\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var requestBuffer = try allocator.alloc(u8, 1024);
    const bytesRead = try connection.stream.read(requestBuffer);

    print("{s}", .{requestBuffer[0..bytesRead]});
    const request = http.Request.parse(requestBuffer[0..bytesRead]);
    print("{any}", .{request});

    var response = http.Response.init(http.HttpStatus.OK);
    const responseBuffer = try allocator.alloc(u8, 1024);
    const answer = try response.serialize(responseBuffer);
    print("sending: {s}", .{answer});
    try connection.stream.writeAll(answer);
    connection.stream.close();
    print("server closed!\n", .{});
}
