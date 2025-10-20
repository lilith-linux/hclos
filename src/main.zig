const std = @import("std");
const fetch = @import("fetch.zig");
const parse = @import("parse.zig");

pub fn main() !void {
    const file = try std.fs.cwd().createFile("./index.htm", .{});

    try fetch.fetch_file("https://example.com", file);

    _ = try parse.parse("./main.zig");
}


