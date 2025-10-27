const std = @import("std");
const package = @import("package");
const constants = @import("constants");
const utils = @import("utils");
const installed = @import("installed");

pub fn unpack(allocator: std.mem.Allocator, package_file: []const u8, package_info: package.structs.Package, prefix: []const u8) !void {
    const name = std.mem.sliceTo(package_info.name, 0);
    const version = std.mem.sliceTo(package_info.version, 0);

    const installed_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, constants.hclos_installed_dir });
    defer allocator.free(installed_dir);
    try utils.makeDirAbsoluteRecursive(allocator, installed_dir);

    const installed_file = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ prefix, constants.hclos_installed_dir, name });
    var file = try std.fs.createFileAbsolute(installed_file, .{});
    var buffer = try allocator.alloc(u8, 2026); // happy new year! (but, today is 10/27)
    const writer = file.writer(&buffer);

    const child = std.process.Child.init(&.{ "tar", "-xvf", package_file, "-C", prefix }, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.stdin_behavior = .Ignore;

    const result = try child.spawnAndWait();

    if (result != .Exited or result.Exited != 0) {
        std.debug.print("\nFailed to unpack package: {s}\n", .{package_file});
        return error.UnpackFailed;
    }

    const stdout = child.stdout.?;
    const reader = stdout.deprecatedReader();
    const stdout_content = try reader.readAllAlloc(allocator, std.math.maxInt(usize));

    const installed_package = installed.structs.InstalledPackage{
        .name = name,
        .version = version,
        .pathlist = try splitToArray(allocator, stdout_content, "\n"),
    };

    try installed.writer.writePackageList(allocator, writer, installed_package);
}

pub fn splitToArray(
    allocator: std.mem.Allocator,
    text: []const u8,
    delimiters: []const u8,
) ![][]const u8 {
    var list = std.ArrayList([]const u8){};
    defer list.deinit(allocator);

    var iter = std.mem.splitAny(u8, text, delimiters);
    while (iter.next()) |part| {
        if (part.len > 0) {
            try list.append(part);
        }
    }

    return list.toOwnedSlice();
}
