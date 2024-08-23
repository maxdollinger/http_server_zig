const std = @import("std");
const assert = std.debug.assert;

pub const Header = struct {
    pub const ContentType: []const u8 = "Content-Type";
    pub const ContentLength: []const u8 = "Content-Length";
    pub const UserAgent: []const u8 = "User-Agent";
};

pub const Headers = struct {
    _map: std.BufMap,

    pub fn init(allocator: std.mem.Allocator) Headers {
        return Headers{
            ._map = std.BufMap.init(allocator),
        };
    }

    pub fn deinit(self: *Headers) void {
        self._map.deinit();
    }

    pub fn add(self: *Headers, name: []const u8, value: []const u8) void {
        self._map.put(name, value) catch |err| {
            std.debug.print("failed to put '{s}: {s}' into header map: {s}", .{ name, value, @errorName(err) });
        };
    }

    pub fn contentType(self: *Headers, value: []const u8) void {
        self._map.put(Header.ContentType, value) catch |err| {
            std.debug.print("failed to insert contentType into headers: {s}", .{@errorName(err)});
        };
    }

    pub fn contentLength(self: *Headers, value: usize) void {
        var buf: [16]u8 = undefined;
        self._map.put(Header.ContentLength, std.fmt.bufPrint(&buf, "{d}", .{value}) catch "0") catch |err| {
            std.debug.print("failed to insert contentType into headers: {s}", .{@errorName(err)});
        };
    }

    pub fn findHeader(self: Headers, header: []const u8) ?[]const u8 {
        return self._map.get(header);
    }

    pub fn getWritten(self: Headers) []const u8 {
        return self.buffer[0..self.len];
    }
};

pub const Status = enum {
    OK,
    CREATED,
    BAD_REQUEST,
    NOT_FOUND,
    SERVER_ERROR,

    pub fn toString(self: Status) []const u8 {
        return switch (self) {
            .OK => "200 OK",
            .CREATED => "201 Created",
            .BAD_REQUEST => "400 Bad Request",
            .NOT_FOUND => "404 Not Found",
            .SERVER_ERROR => "500 Internal Server Error",
        };
    }
};

pub const Result = struct {
    status: Status = Status.OK,
    header: Headers,
    _body: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Result {
        var result = Result{
            .header = Headers.init(allocator),
            ._body = std.ArrayList(u8).init(allocator),
        };
        result.header.contentType("text/plain");
        result.header.contentLength(0);
        return result;
    }

    pub fn deinit(self: *Result) void {
        self.header.deinit();
        self.body.deinit();
    }

    pub fn writeBody(self: *Result, value: []const u8) void {
        self._body.appendSlice(value) catch {
            std.debug.print("failed to write to result body", .{});
        };
        self.header.contentLength(self._body.items.len);
    }

    pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("HTTP/1.1 {s}\r\n", .{self.status.toString()});
        var headerIter = self.header._map.iterator();
        while (headerIter.next()) |entry| {
            writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* }) catch {};
        }
        try writer.print("\r\n", .{});
        try writer.print("{s}", .{self._body.items});
    }

    pub fn send(self: *Result, writer: std.net.Stream.Writer) !void {
        try writer.print("{}", .{self});
    }
};

pub const Request = struct {
    method: []const u8 = "",
    target: []const u8 = "",
    header: Headers,
    body: []const u8 = "",
    raw: std.ArrayList(u8),

    pub fn parse(allocator: std.mem.Allocator, reader: std.net.Stream.Reader) !Request {
        var req = Request{
            .header = Headers.init(allocator),
            .raw = try std.ArrayList(u8).initCapacity(allocator, 2048),
        };

        while (true) {
            const last = req.raw.getLastOrNull() orelse 0;
            try req.raw.append(try reader.readByte());

            if (last == '\n' and req.raw.getLast() == '\r') {
                try req.raw.append(try reader.readByte());
                break;
            }
        }

        var reqIter = std.mem.splitSequence(u8, req.raw.items, "\r\n");
        const statusLine = reqIter.first();
        try req.parseStatusLine(statusLine);

        while (reqIter.next()) |line| {
            if (line.len == 0) break;

            var split = std.mem.splitSequence(u8, line, ": ");
            const name = split.first();
            const value = std.mem.trimRight(u8, split.next() orelse "", "\r\n");
            try req.header._map.put(name, value);
        }

        const contentLengthValue = req.header.findHeader(Header.ContentLength) orelse "0";
        var cLen = std.fmt.parseInt(u8, contentLengthValue, 10) catch 0;

        if (cLen > req.raw.unusedCapacitySlice().len) {
            return std.mem.Allocator.Error.OutOfMemory;
        }

        const bodyStart = req.raw.items.len;
        while (cLen > 0) : (cLen -= 1) {
            try req.raw.append(try reader.readByte());
        }
        req.body = req.raw.items[bodyStart..];

        return req;
    }

    pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s} HTTP/1.1 {s}\r\n", .{ self.method, self.target });
        var headerIter = self.header._map.iterator();
        while (headerIter.next()) |entry| {
            writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* }) catch {};
        }
        try writer.print("\r\n", .{});
        try writer.print("{s}", .{self.body});
    }

    fn parseStatusLine(self: *Request, line: []const u8) !void {
        var splitIter = std.mem.splitScalar(u8, line, ' ');
        self.method = splitIter.first();
        self.target = splitIter.next() orelse "/";
    }
};
