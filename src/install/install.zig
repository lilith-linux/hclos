const std = @import("std");
const fetch = @import("fetch");
const package = @import("package");
const reader = package.reader;
const constants = @import("constants");
const repo_conf = @import("repos_conf");
const info = @import("info").info;
const utils = @import("utils");
const unpack = @import("unpack.zig");
const dependencies = @import("dependencies.zig");
const hash = @import("hash");

const installOptions = struct {
    prefix: []const u8 = "/",
};

pub fn install(pkgs: [][:0]u8, options: installOptions) !void {
    if (!is_root()) {
        std.debug.print("Error: You must run this command as root\n", .{});
        std.process.exit(1);
    }
    const prefix = options.prefix;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const parsed_repos = repo_conf.parse_repos(allocator) catch |err| {
        std.debug.print("Failed to parse repos.toml: {any}\n", .{err});
        std.process.exit(1);
    };

    // create cache directory
    const dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, constants.hclos_cache });
    defer allocator.free(dir);
    try utils.makeDirAbsoluteRecursive(allocator, dir);
    defer deleteTree(dir);

    var install_packages = std.StringHashMap(repo_conf.Repository).init(allocator);
    defer {
        var iter = install_packages.iterator();
        //
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
        const hcl_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}.hcl", .{ prefix, constants.hclos_cache, package_name });
        defer allocator.free(hcl_file_path);

        const hash_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}.hcl.hash", .{ prefix, constants.hclos_cache, package_name });
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
}

fn integrity_check(allocator: std.mem.Allocator, package_name: []const u8, current_index: usize, total_packages: usize, prefix: []const u8) !void {
    try info(allocator, "check: {s} ({d}/{d})", .{ package_name, current_index, total_packages });

    const target_file = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}.hcl", .{ prefix, constants.hclos_cache, package_name });
    defer allocator.free(target_file);

    const hash_file = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}.hcl.hash", .{ prefix, constants.hclos_cache, package_name });
    defer allocator.free(hash_file);

    const expected_hash = try std.fs.cwd().readFileAlloc(allocator, hash_file, 1000);
    defer allocator.free(expected_hash);
    const trimmed = std.mem.trim(u8, expected_hash, &std.ascii.whitespace);

    const generated = try hash.gen_hash(allocator, target_file);
    defer allocator.free(generated);

    if (!std.mem.eql(u8, trimmed, generated)) {
        std.debug.print("\nHash mismatch for package '{s}'\n", .{package_name});
        std.process.exit(1);
    }
}

fn isEmptyString(buf: []const u8) bool {
    return std.mem.indexOfScalar(u8, buf, 0) == 0;
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
