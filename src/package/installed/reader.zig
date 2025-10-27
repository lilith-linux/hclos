const structs = @import("./structs.zig");
const std = @import("std");

pub fn readPackage(allocator: std.mem.Allocator, file: []const u8) !structs.Package {
    const file_opened = try std.fs.cwd().openFile(file, .{});
    defer file_opened.close();

    const stat = try file_opened.stat();
    const content = try file_opened.readToEndAlloc(allocator, stat.size + 1);
    defer allocator.free(content);

    const splited = std.mem.splitAny(u8, content, "\n");

    var name: []u8 = undefined;
    var version: []u8 = undefined;
    var pathlist: []u8 = undefined;

    for (splited) |line| {
        if (line.len == 0) continue;
        const parts = std.mem.splitAny(u8, line, "=");
        if (parts.count() != 2) continue;
        const key = parts.next().?;
        const value = parts.next().?;

        if (std.mem.eql(u8, key, "name")) {
            name = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "version")) {
            version = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "pathlist")) {
            pathlist = try allocator.dupe(u8, value);
        }
    }

    return structs.Package{
        .name = name,
        .version = version,
        .pathlist = pathlist,
    };
}
