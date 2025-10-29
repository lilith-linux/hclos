const std = @import("std");
const package = @import("package");
const constants = @import("constants");
const utils = @import("utils");
const installed = @import("installed");

pub fn unpack(
    allocator: std.mem.Allocator,
    package_file: []const u8,
    package_info: package.structs.Package,
    prefix: []const u8,
) !void {
    const name = std.mem.sliceTo(&package_info.name, 0);
    const version = std.mem.sliceTo(&package_info.version, 0);

    // prefix配下にインストール済みパッケージディレクトリを作成
    const installed_dir = if (std.mem.eql(u8, prefix, "/"))
        constants.hclos_installed_dir
    else
        try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, constants.hclos_installed_dir });

    defer if (!std.mem.eql(u8, prefix, "/")) allocator.free(installed_dir);

    try utils.makeDirAbsoluteRecursive(allocator, installed_dir);

    const installed_file = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ installed_dir, name });
    defer allocator.free(installed_file);

    var file = try std.fs.createFileAbsolute(installed_file, .{});
    defer file.close();

    // tarコマンドでprefix配下に展開
    var child = std.process.Child.init(&.{ "tar", "-xvf", package_file, "-C", prefix }, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    child.stdin_behavior = .Ignore;

    try child.spawn();

    var stdout_content: []u8 = undefined;
    defer allocator.free(stdout_content);

    if (child.stdout) |stdout| {
        const reader = stdout.deprecatedReader();
        stdout_content = try reader.readAllAlloc(allocator, std.math.maxInt(usize));
    } else {
        std.debug.print("\nFailed to unpack package: {s}\n", .{package_file});
        std.process.exit(1);
    }

    const result = try child.wait();

    if (result != .Exited or result.Exited != 0) {
        std.debug.print("\nFailed to unpack package: {s}\n", .{package_file});
        return error.UnpackFailed;
    }

    // パスリストをprefix付きに変換
    const pathlist = try splitToArray(allocator, stdout_content, "\n");
    defer allocator.free(pathlist);

    const prefixed_pathlist = try prefixPaths(allocator, pathlist, prefix);
    defer {
        for (prefixed_pathlist) |path| {
            allocator.free(path);
        }
        allocator.free(prefixed_pathlist);
    }

    const installed_package = installed.structs.InstalledPackage{
        .name = name,
        .version = version,
        .pathlist = prefixed_pathlist,
    };

    try installed.writer.writePackageList(allocator, file, installed_package);
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
            try list.append(allocator, part);
        }
    }

    return list.toOwnedSlice(allocator);
}

fn prefixPaths(
    allocator: std.mem.Allocator,
    paths: [][]const u8,
    prefix: []const u8,
) ![][]const u8 {
    if (std.mem.eql(u8, prefix, "/")) {
        // prefix が "/" の場合はそのまま返す
        var result = try allocator.alloc([]const u8, paths.len);
        for (paths, 0..) |path, i| {
            result[i] = try allocator.dupe(u8, path);
        }
        return result;
    }

    var result = try allocator.alloc([]const u8, paths.len);
    for (paths, 0..) |path, i| {
        // パスがルートから始まる場合
        if (path.len > 0 and path[0] == '/') {
            result[i] = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, path });
        } else {
            // 相対パスの場合（念のため）
            result[i] = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, path });
        }
    }
    return result;
}
