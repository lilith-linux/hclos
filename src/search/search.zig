const std = @import("std");
const repo_conf = @import("repos_conf");
const package = @import("package");
const constants = @import("constants");
const reader = @import("package_reader");

pub fn search(pkgs: [][]const u8) !void {
    const gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    const parsed_repos = repo_conf.parse_repos(allocator) catch |err| {
        std.debug.print("Failed to parse repos.toml: {any}\n", .{err});
        std.process.exit(1);
    };

    for (parsed_repos) |repo| {
        const read_repo = std.fmt.allocPrint(allocator, "{s}/{s}/index.bin", .{ constants.hclos_repos, repo.name });
        defer allocator.free(read_repo);
        var readed = try reader.read_packages(read_repo);
        var db = try package.PackageDB.init(allocator, &readed);
        defer db.deinit();

        for (pkgs) |pkg| {
            if (db.find(pkg)) |found_pkg| {
                std.debug.print("{s} - v{s}: {s}", .{ found_pkg.name, found_pkg.version, found_pkg.description });
            } else {
                std.debug.print("Package not found: {s}", .{pkg});
                std.process.exit(1);
            }
        }
    }
}
