const std = @import("std");

pub fn info(allocator: std.mem.Allocator, comptime text: []const u8, fmt: anytype) !void {
    const stdout = std.fs.File.stdout();
    const formatted = try std.fmt.allocPrint(allocator, "\r\x1b[2K" ++ text, fmt);
    defer allocator.free(formatted);
    try stdout.writeAll(formatted);
}
