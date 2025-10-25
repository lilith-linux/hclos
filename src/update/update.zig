const std = @import("std");
const constants = @import("constants");
const repos_conf = @import("repos_conf");
const fetch = @import("fetch");
const hash = @import("hash");
const info = @import("info").info;

pub fn update_repo() !void {
    if (!is_root()) {
        std.debug.print("Not running as root\n", .{});
        std.debug.print("Exit.\n", .{});
        std.process.exit(1);
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alc = gpa.allocator();

    const repos = try repos_conf.parse_repos(alc);
    defer repos.deinit();

    for (repos.value.repo) |repo| {
        try info(alc, "fetch: {s}", .{repo.name});
        fetch_files(alc, repo.name, repo.url) catch |err| {
            std.debug.print("\nFailed to fetch {s}: {any}\n", .{ repo.name, err });
            return;
        };
        const result = try check_hash(alc, repo.name);
        if (!result) {
            std.debug.print("\nHash missmatch: {s}\n", .{repo.name});
        }
    }
    std.debug.print("\n", .{});
}

fn fetch_files(alc: std.mem.Allocator, name: []const u8, url: []const u8) !void {
    const url_bin = try std.fmt.allocPrint(alc, "{s}/index.bin", .{url});
    const url_bin_hash = try std.fmt.allocPrint(alc, "{s}/index.bin.hash", .{url});

    const savedir = try std.fmt.allocPrint(alc, "{s}/{s}", .{ constants.hclos_repos, name });
    const save_bin = try std.fmt.allocPrint(alc, "{s}/index.bin", .{savedir});
    const save_bin_hash = try std.fmt.allocPrint(alc, "{s}/index.bin.hash", .{savedir});

    const url_bin_z = try alc.dupeZ(u8, url_bin);
    const url_bin_hash_z = try alc.dupeZ(u8, url_bin_hash);

    defer alc.free(url_bin_z);
    defer alc.free(url_bin_hash_z);

    defer alc.free(url_bin);
    defer alc.free(savedir);
    defer alc.free(save_bin);
    defer alc.free(save_bin_hash);

    if (!exists(savedir)) {
        try std.fs.makeDirAbsolute(savedir);
    }

    var file_bin = std.fs.createFileAbsolute(save_bin, .{}) catch |err| {
        std.debug.print("\nFailed to create {s}: {any}\n", .{ save_bin, err });
        return;
    };
    defer file_bin.close();

    var file_hash = std.fs.createFileAbsolute(save_bin_hash, .{}) catch |err| {
        std.debug.print("\nFailed to create {s}: {any}\n", .{ save_bin, err });
        return;
    };
    defer file_hash.close();

    fetch.fetch_file(url_bin_z, &file_bin) catch |err| {
        std.debug.print("\r\x1b[2Kfailed: {s} -- {any}\n", .{ name, err });
        std.process.exit(1);
    };
    fetch.fetch_file(url_bin_hash_z, &file_hash) catch |err| {
        std.debug.print("\r\x1b[2Kfailed: {s} -- {any}\n", .{ name, err });
        std.process.exit(1);
    };
}

pub fn check_hash(alc: std.mem.Allocator, name: []const u8) !bool {
    const savedir = try std.fmt.allocPrint(alc, "{s}/{s}", .{ constants.hclos_repos, name });
    defer alc.free(savedir);

    const bin = try std.fmt.allocPrint(alc, "{s}/index.bin", .{savedir});
    defer alc.free(bin);

    const bin_hash = try std.fmt.allocPrint(alc, "{s}/index.bin.hash", .{savedir});
    defer alc.free(bin_hash);

    const bin_expected_file = try std.fs.openFileAbsolute(bin_hash, .{});
    const expected_hash = try bin_expected_file.readToEndAlloc(alc, 1024);
    defer alc.free(expected_hash);
    const trimmed = std.mem.trim(u8, expected_hash, &std.ascii.whitespace);

    const index_hash = try hash.gen_hash(alc, bin);
    defer alc.free(index_hash);


    if (std.mem.eql(u8, index_hash, trimmed)) {
        return true;
    }
    return false;
}

fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn is_root() bool {
    return std.os.linux.getuid() == 0;
}
