const structs = @import("./structs.zig");
const std = @import("std");

pub fn writePackageList(allocator: std.mem.Allocator, file: std.fs.File, package: structs.InstalledPackage) !void {
    const name = try std.fmt.allocPrint(allocator, "name={s}\n", .{package.name});
    defer allocator.free(name);

    const version = try std.fmt.allocPrint(allocator, "version={s}\n", .{package.version});
    defer allocator.free(version);
    const joined = try std.mem.join(allocator, ":", package.pathlist);
    defer allocator.free(joined);
    const pathlist = try std.fmt.allocPrint(allocator, "pathlist={s}\n", .{joined});
    defer allocator.free(pathlist);

    try file.writeAll(name);
    try file.writeAll(version);
    try file.writeAll(pathlist);
}
