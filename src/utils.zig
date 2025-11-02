const std = @import("std");
const fetch = @import("fetch");
const package = @import("package");

pub fn makeDirAbsoluteRecursive(allocator: std.mem.Allocator, dir_path: []const u8) !void {
    var parts = std.mem.splitSequence(u8, dir_path, "/");
    var current_path = std.ArrayList(u8){};
    defer current_path.deinit(allocator);

    if (dir_path.len > 0 and dir_path[0] == '/') {
        try current_path.append(allocator, '/');
    }

    while (parts.next()) |part| {
        if (part.len == 0) continue;

        if (current_path.items.len > 1) {
            try current_path.append(allocator, '/');
        }
        try current_path.appendSlice(allocator, part);

        std.fs.makeDirAbsolute(current_path.items) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };
    }
}

pub fn isValidPackage(pkg: *const package.structs.Package) bool {
    // 名前の最初の文字をチェック
    if (pkg.name[0] == 0) return false;

    // 印刷可能なASCII文字で始まるかチェック
    if (pkg.name[0] < 32 or pkg.name[0] > 126) return false;

    // 名前の長さを確認（ゼロバイトまで）
    const name_end = std.mem.indexOfScalar(u8, &pkg.name, 0) orelse pkg.name.len;
    if (name_end == 0 or name_end > 32) return false;

    // 名前が有効なASCII文字のみで構成されているか
    for (pkg.name[0..name_end]) |c| {
        if (c < 32 or c > 126) return false;
    }

    return true;
}

pub fn deleteFile(path: []const u8) void {
    std.fs.cwd().deleteFile(path) catch |err| {
        if (err != error.FileNotFound) {
            std.log.err("Failed to delete file: {any}", .{err});
        }
    };
}

pub fn copyFile(allocator: std.mem.Allocator, src_path: []const u8, dest_path: []const u8) !void {
    const src_file = try std.fs.openFileAbsolute(src_path, .{ .mode = .read_only });
    defer src_file.close();

    const dest_file = try std.fs.createFileAbsolute(dest_path, .{});
    defer dest_file.close();

    try dest_file.writeAll(src_file.deprecatedReader().readAllAlloc(allocator, std.math.maxInt(usize)) catch unreachable);
}

pub fn download(allocator: std.mem.Allocator, url: []const u8, path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    const url_z = try allocator.dupeZ(u8, url);
    defer allocator.free(url_z);

    try fetch.fetch_file(url_z, &file);
}
