const std = @import("std");
const fetch = @import("fetch");
const package = @import("package");
const reader = @import("package_reader");
const constants = @import("constants");
const repo_conf = @import("repos_conf");

pub fn install(pkgs: [][:0]u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const parsed_repos = repo_conf.parse_repos(allocator) catch |err| {
        std.debug.print("Failed to parse repos.toml: {any}\n", .{err});
        std.process.exit(1);
    };

    var install_packages = try std.ArrayList(package.Package).initCapacity(allocator, 20);
    defer install_packages.deinit(allocator);

    // search packages
    for (pkgs) |pkg| {
        for (parsed_repos.value.repo) |repo| {
            const read_repo = try std.fmt.allocPrint(allocator, "{s}/{s}/index.bin", .{ constants.hclos_repos, repo.name });
            defer allocator.free(read_repo);
            const readed = try reader.read_packages(read_repo);
            var db = try package.PackageDB.init(allocator, &readed);
            defer db.deinit();

            if (db.find(pkg)) |found_pkg| {
                try install_packages.append(allocator, found_pkg.*);
                break;
            } else {
                std.debug.print("Package not found: {s}\n", .{pkg});
                std.process.exit(1);
            }
        }
    }

    for (install_packages.items) |pkg| {
        std.debug.print("==== found package {s} ====\n", .{pkg.name});
        std.debug.print("description: {s}\n", .{pkg.description});
        std.debug.print("license: {s}\n", .{pkg.license});
        std.debug.print("version: {s}\n", .{pkg.version});
        var depends = std.ArrayList([]u8){};
        defer {
            for (depends.items) |item| {
                allocator.free(item);
            }
            depends.deinit(allocator);
        }

        for (pkg.depend) |dep| {
            if (isEmptyString(&dep)) {
                continue;
            }
            const depend = try allocator.dupe(u8, &dep);
            try depends.append(allocator, depend);
        }

        const deps = try std.mem.join(allocator, ", ", depends.items);
        defer allocator.free(deps);

        std.debug.print("dependencies: {s}\n", .{deps});
    }
}

fn isEmptyString(buf: []const u8) bool {
    return std.mem.indexOfScalar(u8, buf, 0) == 0;
}
