const std = @import("std");
const http = @import("http.zig");

pub const Route = struct {
    match: *const fn (*http.Request) bool,
    handler: *const fn (*http.Request, *http.Result) void,
};

pub const Router = struct {
    routes: std.ArrayList(Route),

    pub fn init(allocator: std.mem.Allocator) Router {
        return Router{
            .routes = std.ArrayList(Route).init(allocator),
        };
    }

    const Self = @This();

    pub fn addRoute(self: *Self, route: Route) void {
        self.routes.append(route) catch {};
    }

    pub fn handle(self: Self, req: *http.Request, res: *http.Result) void {
        for (self.routes.items) |route| {
            if (route.match(req)) {
                route.handler(req, res);
                return;
            }
        }

        res.status = http.Status.NOT_FOUND;
    }
};
