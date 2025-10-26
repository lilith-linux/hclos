const std = @import("std");
const fetch = @import("fetch");
const package = @import("package");
const reader = @import("package_reader");
const constants = @import("constants");
const repo_conf = @import("repos_conf");
const info = @import("info").info;

pub fn install(pkgs: [][:0]u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const parsed_repos = repo_conf.parse_repos(allocator) catch |err| {
        std.debug.print("Failed to parse repos.toml: {any}\n", .{err});
        std.process.exit(1);
    };

    var install_packages = std.StringHashMap(repo_conf.Repository).init(allocator);
    defer install_packages.deinit();

    // search packages
    for (pkgs) |pkg| {
        for (parsed_repos.value.repo) |repo| {
            const read_repo = try std.fmt.allocPrint(allocator, "{s}/{s}/index.bin", .{ constants.hclos_repos, repo.name });
            defer allocator.free(read_repo);
            const readed = try reader.read_packages(allocator, read_repo);
            defer allocator.destroy(readed);

            var db = try package.PackageDB.init(allocator, &readed.*);
            defer db.deinit();

            if (db.find(pkg)) |found_pkg| {
                const duped = try allocator.dupe(u8, &found_pkg.name);
                try install_packages.put(duped, repo);
                break;
            } else {
                std.debug.print("Package not found: {s}\n", .{pkg});
                std.process.exit(1);
            }
        }
    }

    var iterator = install_packages.iterator();

    while (iterator.next()) |iter| {
        const key = iter.key_ptr.*;
        const name = std.mem.sliceTo(key, 0);
        const repo = iter.value_ptr.*;

        try info(allocator, "fetch: {s}", .{name});

        const fetch_url = try std.fmt.allocPrint(allocator, "{s}/package/{s}", .{ repo.url, name });
        defer allocator.free(fetch_url);
        const z = try allocator.dupeZ(u8, fetch_url);
        defer allocator.free(z);

        try makeDirAbsoluteRecursive(allocator, "/var/cache/hclos/downloads");
        const cache_file = try std.fmt.allocPrint(allocator, "/var/cache/hclos/downloads/{s}.hcl", .{name});
        defer allocator.free(cache_file);

        var file = try std.fs.createFileAbsolute(cache_file, .{});
        try fetch.fetch_file(z, &file);
    }
    std.debug.print("\n", .{});
}

fn isEmptyString(buf: []const u8) bool {
    return std.mem.indexOfScalar(u8, buf, 0) == 0;
}

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
