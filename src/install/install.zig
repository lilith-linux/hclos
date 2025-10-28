const std = @import("std");
const fetch = @import("fetch");
const package = @import("package");
const reader = package.reader;
const constants = @import("constants");
const repo_conf = @import("repos_conf");
const info = @import("info").info;
const utils = @import("utils");
const unpack = @import("unpack.zig");
const scripts = @import("scripts");
const dependencies = @import("dependencies.zig");
const hash = @import("hash");

pub const InstallOptions = struct {
    prefix: []const u8 = "/",
};

pub fn install(allocator: std.mem.Allocator, pkgs: [][:0]u8, options: InstallOptions) !void {
    const prefix = try std.fs.realpathAlloc(allocator, options.prefix);
    defer allocator.free(prefix);

    try install_package(allocator, pkgs, prefix);
}

pub fn install_package(allocator: std.mem.Allocator, pkgs: [][:0]u8, prefix: []const u8) !void {
    if (!is_root()) {
        std.debug.print("Error: You must run this command as root\n", .{});
        std.process.exit(1);
    }

    const parsed_repos = repo_conf.parse_repos(allocator) catch |err| {
        std.debug.print("Failed to parse repos.toml: {any}\n", .{err});
        std.process.exit(1);
    };

    // create cache directory
    const prefix_cache = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, constants.hclos_cache });
    defer deleteTree(prefix_cache);

    // prefix cache の作成
    try utils.makeDirAbsoluteRecursive(allocator, prefix_cache);

    var install_packages = std.StringHashMap(repo_conf.Repository).init(allocator);
    defer {
        var iter = install_packages.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        install_packages.deinit();
    }

    // === 依存関係を解決 ===
    var dependency_tree = try dependencies.resolveDependencies(
        allocator,
        pkgs,
        &parsed_repos.value,
        &install_packages,
        prefix,
    );
    defer {
        var iter = dependency_tree.iterator();
        while (iter.next()) |entry| {
            var node = entry.value_ptr;
            node.deinit(allocator);
            allocator.free(entry.key_ptr.*);
        }
        dependency_tree.deinit();
    }

    // 依存関係ツリーを表示
    try dependencies.printDependencyTree(allocator, pkgs, &dependency_tree);

    var iterator = install_packages.iterator();
    var iterator_for_integrity = install_packages.keyIterator();

    var total_packages: usize = 0;

    // fetch packages
    while (iterator.next()) |iter| {
        total_packages += 1;
        const key = iter.key_ptr.*;
        const package_name = std.mem.sliceTo(key, 0);
        const repo = iter.value_ptr.*;

        try info(allocator, "fetch: {s}", .{package_name});

        // hcl(binary) package
        const hcl_url = try std.fmt.allocPrint(allocator, "{s}/packages/{s}.hcl", .{ repo.url, package_name });
        defer allocator.free(hcl_url);

        // hash file for <package>.hcl
        const hash_url = try std.fmt.allocPrint(allocator, "{s}/packages/{s}.hcl.hash", .{ repo.url, package_name });
        defer allocator.free(hash_url);

        const z_hcl = try allocator.dupeZ(u8, hcl_url);
        const z_hash = try allocator.dupeZ(u8, hash_url);
        defer allocator.free(z_hash);
        defer allocator.free(z_hcl);

        // download package location
        const hcl_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}.hcl", .{ prefix_cache, package_name });
        defer allocator.free(hcl_file_path);

        const hash_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}.hcl.hash", .{ prefix_cache, package_name });
        defer allocator.free(hash_file_path);

        var hcl_file = try std.fs.createFileAbsolute(hcl_file_path, .{});
        defer hcl_file.close();

        var hash_file = try std.fs.createFileAbsolute(hash_file_path, .{});
        defer hash_file.close();

        try fetch.fetch_file(z_hcl, &hcl_file);
        std.debug.print("fetch: {s} - hash", .{package_name});
        try fetch.fetch_file(z_hash, &hash_file);
    }
    std.debug.print("\n", .{});

    var current: usize = 0;
    // check integrity
    while (iterator_for_integrity.next()) |iter| {
        current += 1;
        const key = iter.*;
        const pkg_name = std.mem.sliceTo(key, 0);
        integrity_check(allocator, pkg_name, current, total_packages, prefix) catch |err| {
            std.debug.print("\r\x1b[2KError: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
    }
    std.debug.print("\n", .{});

    // === unpack packages ===
    current = 0;
    var iterator_for_unpack = install_packages.iterator();

    while (iterator_for_unpack.next()) |iter| {
        current += 1;
        const key = iter.key_ptr.*;
        const pkg_name = std.mem.sliceTo(key, 0);
        const repo = iter.value_ptr.*;

        try info(allocator, "unpack: {s} ({d}/{d})", .{ pkg_name, current, total_packages });

        const pkg_info = try getPackageInfo(allocator, pkg_name, repo, prefix);

        const hcl_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}.hcl", .{ prefix_cache, pkg_name });
        defer allocator.free(hcl_file_path);

        // unpack with prefix
        unpack.unpack(allocator, hcl_file_path, pkg_info, prefix) catch |err| {
            std.debug.print("\r\x1b[2KError unpacking {s}: {s}\n", .{ pkg_name, @errorName(err) });
            std.process.exit(1);
        };
    }
    std.debug.print("\n", .{});

    std.debug.print("Installation completed successfully to: {s}\n", .{prefix});
}

fn getPackageInfo(
    allocator: std.mem.Allocator,
    pkg_name: []const u8,
    repo: repo_conf.Repository,
    prefix: []const u8,
) !package.structs.Package {
    const prefix_cache = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, constants.hclos_repos });
    const read_repo = try std.fmt.allocPrint(allocator, "{s}/{s}/index.bin", .{ prefix_cache, repo.name });
    defer allocator.free(read_repo);

    const readed = try reader.read_packages(allocator, read_repo);
    defer allocator.destroy(readed);

    var db = try package.structs.PackageDB.init(allocator, &readed.*);
    defer db.deinit();

    if (db.find(pkg_name)) |pkg| {
        return pkg.*;
    }

    std.debug.print("Package not found: {s}\n", .{pkg_name});
    std.process.exit(1);
}

fn integrity_check(allocator: std.mem.Allocator, package_name: []const u8, current_index: usize, total_packages: usize, prefix: []const u8) !void {
    const prefix_cache = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, constants.hclos_cache });
    defer allocator.free(prefix_cache);

    try info(allocator, "check: {s} ({d}/{d})", .{ package_name, current_index, total_packages });

    const target_file = try std.fmt.allocPrint(allocator, "{s}/{s}.hcl", .{ prefix_cache, package_name });
    defer allocator.free(target_file);

    const hash_file = try std.fmt.allocPrint(allocator, "{s}/{s}.hcl.hash", .{ prefix_cache, package_name });
    defer allocator.free(hash_file);

    const expected_hash = try std.fs.cwd().readFileAlloc(allocator, hash_file, 1000);
    defer allocator.free(expected_hash);
    const trimmed = std.mem.trim(u8, expected_hash, &std.ascii.whitespace);

    const generated = try hash.gen_hash(allocator, target_file);
    defer allocator.free(generated);

    if (!std.mem.eql(u8, trimmed, generated)) {
        std.debug.print("\nhash mismatch for package '{s}'\n", .{package_name});
        std.process.exit(1);
    }
}

fn is_root() bool {
    return std.os.linux.getuid() == 0;
}

fn deleteTree(path: []const u8) void {
    std.fs.cwd().deleteTree(path) catch |err| {
        std.debug.print("Delete file failed: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
