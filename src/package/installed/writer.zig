const structs = @import("./structs.zig");
const std = @import("std");

pub fn writePackageList(allocator: std.mem.Allocator, file: std.fs.File, package: structs.InstalledPackage) !void {
    const name = try std.fmt.allocPrint(allocator, "name={s}\n", .{package.name});
    defer allocator.free(name);

    const version = try std.fmt.allocPrint(allocator, "version={s}\n", .{package.version});
    defer allocator.free(version);

    const pathlist_joined = try std.mem.join(allocator, ":", package.pathlist);
    defer allocator.free(pathlist_joined);
    const pathlist = try std.fmt.allocPrint(allocator, "pathlist={s}\n", .{pathlist_joined});
    defer allocator.free(pathlist);

    const depends_joined = try std.mem.join(allocator, ":", package.depends);
    defer allocator.free(depends_joined);

    const deps = try std.fmt.allocPrint(allocator, "depends={s}\n", .{depends_joined});
    defer allocator.free(deps);

    try file.writeAll(name);
    try file.writeAll(version);
    try file.writeAll(deps);
    try file.writeAll(pathlist);
}
