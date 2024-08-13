const std = @import("std");
const utils = @import("./utils.zig");

pub const Request = struct {
    method: utils.HttpMethod,
    target: []const u8,
    version: utils.HttpVersion,
    header: []const u8,
    body: ?[]const u8,

    pub fn parse(input: []const u8) !Request {
        const request: Request = undefined;

        var i: usize = 0;
        var last: usize = 0;
        var status: []const u8 = "";
        var header: []const u8 = undefined;
        var body: ?[]const u8 = null;
        while (i < input.len) : (i += 1) {
            const seq = if (i > 1) input[i - 1 .. i + 1] else null;
            if (seq != null and std.mem.eql(u8, seq.?, "\r\n")) {
                if (status.len == 0) {
                    status = input[0 .. i - 1];
                } else if (last + 2 == i) {
                    header = input[status.len + 2 .. last - 1];
                    if (i + 1 < input.len - 1) {
                        body = input[i + 1 ..];
                    }
                }
                last = i;
            }
        }

        std.debug.print("Status: {s}\n", .{status});
        std.debug.print("Header: {s}\n", .{header});
        std.debug.print("Body: {any}\n", .{body});

        return request;
    }
};
