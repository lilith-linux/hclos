const std = @import("std");
const repo_conf = @import("repos_conf");
const package = @import("package");
const reader = package.reader;
const structs = package.structs;
const constants = @import("constants");

pub fn search(allocator: std.mem.Allocator, pkgs: [][]const u8) !void {
    const parsed_repos = repo_conf.parse_repos(allocator) catch |err| {
        std.debug.print("Failed to parse repos.toml: {any}\n", .{err});
        std.process.exit(1);
    };
    defer parsed_repos.deinit();

    for (pkgs) |pkg| {
        for (parsed_repos.value.repo) |repo| {
            const read_repo = try std.fmt.allocPrint(allocator, "{s}/{s}/index", .{ constants.hclos_repos, repo.name });
            defer allocator.free(read_repo);
            const readed = try reader.read_packages(allocator, read_repo);
            var db = try structs.PackageDB.init(allocator, &readed.*);
            defer db.deinit();

            if (db.find(pkg)) |found_pkg| {
                std.debug.print("{s} - v{s}: {s}\n", .{ found_pkg.name, found_pkg.version, found_pkg.description });
                break;
            } else {
                std.debug.print("Package not found: {s}\n", .{pkg});
                std.process.exit(1);
            }
        }
    }
}
