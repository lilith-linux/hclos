const std = @import("std");
const fetch = @import("fetch");
const package = @import("package");
const reader = @import("package_reader");
const constants = @import("constants");
const repo_conf = @import("repos_conf");

pub fn install(pkgs: [][:0]u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    const parsed_repos = repo_conf.parse_repos(allocator) catch |err| {
        std.debug.print("Failed to parse repos.toml: {any}\n", .{err});
        std.process.exit(1);
    };

    var install_packages = try std.ArrayList(package.Package).initCapacity(allocator, 20);
    defer install_packages.deinit(allocator);

    for (parsed_repos.value.repo) |repo| {
        for (pkgs) |pkg| {
            const read_repo = try std.fmt.allocPrint(allocator, "{s}/{s}/index.bin", .{ constants.hclos_repos, repo.name });
            defer allocator.free(read_repo);
            const readed = try reader.read_packages(read_repo);
            var db = try package.PackageDB.init(allocator, &readed);
            defer db.deinit();

            if (db.find(pkg)) |found_pkg| {
                try install_packages.append(allocator, found_pkg.*);
            } else {
                std.debug.print("Package not found: {s}", .{pkg});
                std.process.exit(1);
            }
        }
    }
}
