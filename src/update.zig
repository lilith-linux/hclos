const std = @import("std");
const contstants = @import("constants.zig");
const repos_conf = @import("repos_conf.zig");
const fetch = @import("fetch.zig");
const _info = @import("info.zig");
const info = _info.info;


pub fn update_repo() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alc = gpa.allocator();

    const repos = try repos_conf.parse_repos(alc);
    defer repos.deinit();

    for (repos.value.repo) |repo| {
        try info(alc, "fetch: {s}", .{repo.name});
        const url_bin = try std.fmt.allocPrint(alc, "{s}/index.bin", .{repo.url});
        const url_bin_minisig = try std.fmt.allocPrint(alc, "{s}/index.bin.minisig", .{repo.url});
        const url_minisig_pub = try std.fmt.allocPrint(alc, "{s}/{s}.pub", .{repo.url, repo.name});

        const savedir = try std.fmt.allocPrint(alc, "{s}/{s}", .{contstants.hclos_repos, repo.name});
        const save_bin = try std.fmt.allocPrint(alc, "{s}/index.bin", .{savedir});
        const save_bin_minisig = try std.fmt.allocPrint(alc, "{s}/index.bin.minisig", .{savedir});
        const save_minisig_pub = try std.fmt.allocPrint(alc, "{s}/{s}.pub", .{savedir, repo.name});

        const url_bin_z = try alc.dupeZ(u8, url_bin);
        const url_bin_minisig_z = try alc.dupeZ(u8, url_bin_minisig);
        const url_minisig_pub_z = try alc.dupeZ(u8, url_minisig_pub);

        defer alc.free(url_bin_z);
        defer alc.free(url_bin_minisig_z);
        defer alc.free(url_minisig_pub_z);

        defer alc.free(url_bin);
        defer alc.free(savedir);
        defer alc.free(save_bin);
        defer alc.free(save_bin_minisig);
        defer alc.free(save_minisig_pub);

        if (!exists(savedir)) {
            try std.fs.makeDirAbsolute(savedir);
        }

        var file_bin = std.fs.createFileAbsolute(save_bin, .{}) catch |err| {
            std.debug.print("\nFailed to create {s}: {any}\n", .{save_bin, err}); 
            return;
        };
        defer file_bin.close();

        var file_minisig = std.fs.createFileAbsolute(save_bin_minisig, .{}) catch |err| {
            std.debug.print("\nFailed to create {s}: {any}\n", .{save_bin, err}); 
            return;
        };
        defer file_minisig.close();

        var file_pub = std.fs.createFileAbsolute(save_minisig_pub, .{}) catch |err| {
            std.debug.print("\nFailed to create {s}: {any}\n", .{save_bin, err}); 
            return;
        };
        defer file_pub.close();

        fetch.fetch_file(url_bin_z, &file_bin) catch |err| {
            std.debug.print("\r\x1b[2Kfailed: {s} -- {any}\n", .{repo.name, err});
            std.process.exit(1);
        };
        fetch.fetch_file(url_bin_minisig_z, &file_minisig) catch |err| {
            std.debug.print("\r\x1b[2Kfailed: {s} -- {any}\n", .{repo.name, err});
            std.process.exit(1);
        };
        fetch.fetch_file(url_minisig_pub_z, &file_pub) catch |err| {
            std.debug.print("\r\x1b[2Kfailed: {s} -- {any}\n", .{repo.name, err});
            std.process.exit(1);
        };

    }
}


fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}
