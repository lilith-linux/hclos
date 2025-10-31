const std = @import("std");
const zstd = std.compress.zstd;
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

    // tarファイルを展開してパスリストを取得
    const pathlist = try unpackTarZstd(allocator, package_file, prefix);
    defer {
        for (pathlist) |path| {
            allocator.free(path);
        }
        allocator.free(pathlist);
    }

    // パスリストをprefix付きに変換
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

fn unpackTarZstd(
    allocator: std.mem.Allocator,
    package_file: []const u8,
    prefix: []const u8,
) ![][]const u8 {
    // パッケージファイルを開く
    const file = try std.fs.openFileAbsolute(package_file, .{});
    defer file.close();

    var buffer_iface: [9 * 1024 * 1024]u8 = undefined;

    var interface = file.reader(&buffer_iface).interface;
    const compressed_reader: *std.Io.Reader = &interface;

    var window_buf: [zstd.default_window_len + zstd.block_size_max + 1]u8 = undefined;

    var zstd_stream = zstd.Decompress.init(compressed_reader, &window_buf, .{});
    const uncompressed_reader = &zstd_stream.reader;

    // tarアーカイブを処理
    var pathlist = std.ArrayList([]const u8){};
    errdefer {
        for (pathlist.items) |path| {
            allocator.free(path);
        }
        pathlist.deinit(allocator);
    }

    // prefixディレクトリを開く
    var prefix_dir = try std.fs.openDirAbsolute(prefix, .{});
    defer prefix_dir.close();

    const file_name_buf: []u8 = undefined;
    const link_name_buf: []u8 = undefined;

    var tar_iter = std.tar.Iterator.init(uncompressed_reader, .{ .file_name_buffer = file_name_buf, .link_name_buffer = link_name_buf });

    while (try tar_iter.next()) |tar_file| {
        switch (tar_file.kind) {
            .directory => {
                // ディレクトリを作成
                try prefix_dir.makePath(tar_file.name);
                const path = try allocator.dupe(u8, tar_file.name);
                try pathlist.append(allocator, path);
            },
            .file => {
                // 親ディレクトリが存在することを確認
                if (std.fs.path.dirname(tar_file.name)) |dir_name| {
                    try prefix_dir.makePath(dir_name);
                }

                // ファイルを作成
                var out_file = try prefix_dir.createFile(tar_file.name, .{
                    .mode = tar_file.mode,
                });
                defer out_file.close();

                var buffer: [2 * 1024]u8 = undefined;

                var file_writer = file.writer(&buffer);
                try tar_iter.streamRemaining(tar_file, &file_writer.interface);
                const path = try allocator.dupe(u8, tar_file.name);
                try pathlist.append(allocator, path);
            },
            .sym_link => {
                // 親ディレクトリが存在することを確認
                if (std.fs.path.dirname(tar_file.name)) |dir_name| {
                    try prefix_dir.makePath(dir_name);
                }

                // シンボリックリンクを作成
                prefix_dir.symLink(tar_file.link_name, tar_file.name, .{}) catch |err| {
                    std.debug.print("Warning: Failed to create symlink {s} -> {s}: {}\n", .{
                        tar_file.name,
                        tar_file.link_name,
                        err,
                    });
                };

                const path = try allocator.dupe(u8, tar_file.name);
                try pathlist.append(allocator, path);
            },
        }
    }

    return try pathlist.toOwnedSlice(allocator);
}

pub fn splitToArray(
    allocator: std.mem.Allocator,
    text: []const u8,
    delimiters: []const u8,
) ![][]const u8 {
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    var iter = std.mem.splitAny(u8, text, delimiters);
    while (iter.next()) |part| {
        if (part.len > 0) {
            try list.append(part);
        }
    }

    return try list.toOwnedSlice();
}

fn prefixPaths(
    allocator: std.mem.Allocator,
    paths: [][]const u8,
    prefix: []const u8,
) ![][]const u8 {
    if (std.mem.eql(u8, prefix, "/")) {
        // prefix が "/" の場合はパスの先頭に "/" を追加
        var result = try allocator.alloc([]const u8, paths.len);
        for (paths, 0..) |path, i| {
            if (path.len > 0 and path[0] == '/') {
                result[i] = try allocator.dupe(u8, path);
            } else {
                result[i] = try std.fmt.allocPrint(allocator, "/{s}", .{path});
            }
        }
        return result;
    }

    var result = try allocator.alloc([]const u8, paths.len);
    for (paths, 0..) |path, i| {
        // パスがルートから始まる場合
        if (path.len > 0 and path[0] == '/') {
            result[i] = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, path });
        } else {
            // 相対パスの場合
            result[i] = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, path });
        }
    }
    return result;
}
