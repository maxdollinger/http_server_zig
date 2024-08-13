const std = @import("std");

pub const HttpVersion = enum {
    http_1,

    pub fn toString(self: HttpVersion) []const u8 {
        return switch (self) {
            .http_1 => "HTTP/1.1",
        };
    }

    pub fn fromString(s: []const u8) !HttpVersion {
        if (std.mem.eql(u8, s, "HTTP/1.1")) return .http_1;
        return HttpErrors.UnknownMethod;
    }
};

pub const HttpErrors = error{
    UnknownMethod,
};

pub const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,

    pub fn fromString(string: []const u8) !HttpMethod {
        if (std.mem.eql(u8, string, "GET")) return .GET;
        if (std.mem.eql(u8, string, "POST")) return .POST;

        return HttpErrors.UnknownMethod;
    }
};
