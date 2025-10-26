const std = @import("std");
const package = @import("package");

pub fn read_packages(path: []const u8) !package.Packages {
    var packages: package.Packages = undefined;

    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    const stat = try file.stat();
    const expected_size = @sizeOf(package.Packages);

    // std.debug.print("File size: {}, Expected: {}\n", .{ stat.size, expected_size });

    if (stat.size < expected_size) {
        return error.PackagesBinFileTooSmall;
    }

    try file.deprecatedReader().readNoEof(std.mem.asBytes(&packages));
    return packages;
}
