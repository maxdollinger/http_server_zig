const io = @import("std").io;
const fmt = @import("std").fmt;

pub const HttpVersion = enum {
    http_1,

    pub fn toString(self: HttpVersion) []const u8 {
        return switch (self) {
            .http_1 => "HTTP/1.1",
        };
    }
};

pub const HttpStatus = enum {
    OK,

    pub fn toString(self: HttpStatus) []const u8 {
        return switch (self) {
            .OK => "200 OK",
        };
    }
};

pub const Response = struct {
    version: HttpVersion,
    status: HttpStatus,
    headers: []const u8,
    body: []const u8,

    pub fn init(status: HttpStatus) Response {
        return Response{ .version = HttpVersion.http_1, .status = status, .headers = "", .body = "" };
    }

    pub fn serialize(self: *Response, buffer: []u8) ![]const u8 {
        var stream = io.fixedBufferStream(buffer);
        const writer = stream.writer();
        try fmt.format(writer, "{s} {s} \r\n{s}\r\n{s}", .{ self.version.toString(), self.status.toString(), self.headers, self.body });

        return stream.getWritten();
    }
};
