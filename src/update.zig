const std = @import("std");
const contstants = @import("constants.zig");
const mirror = @import("mirrors.zig");

pub fn update_repo() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alc = gpa.allocator();

    const mirrors = try mirror.parse_mirrors(alc);

    _ = mirrors;
}
