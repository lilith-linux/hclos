const std = @import("std");
const package = @import("package");

pub fn read_packages(path: []const u8) !package.Packages {
    var packages: package.Packages = undefined;

    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    try file.deprecatedReader().readNoEof(std.mem.asBytes(&packages));
    return packages;
}
