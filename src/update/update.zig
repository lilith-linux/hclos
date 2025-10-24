const std = @import("std");
const constants = @import("constants");
const repos_conf = @import("repos_conf");
const fetch = @import("fetch");
const minisign = @import("minisign");
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
        try check_minisign(alc, repo.name);
    }
    std.debug.print("\n", .{});
}

fn fetch_files(alc: std.mem.Allocator, name: []const u8, url: []const u8) !void{
        const url_bin = try std.fmt.allocPrint(alc, "{s}/index.bin", .{url});
        const url_bin_minisig = try std.fmt.allocPrint(alc, "{s}/index.bin.minisig", .{url});
        const url_minisig_pub = try std.fmt.allocPrint(alc, "{s}/{s}.pub", .{ url, name });

        const savedir = try std.fmt.allocPrint(alc, "{s}/{s}", .{ constants.hclos_repos, name });
        const save_bin = try std.fmt.allocPrint(alc, "{s}/index.bin", .{savedir});
        const save_bin_minisig = try std.fmt.allocPrint(alc, "{s}/index.bin.minisig", .{savedir});
        const save_minisig_pub = try std.fmt.allocPrint(alc, "{s}/{s}.pub", .{ savedir, name });

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
            std.debug.print("\nFailed to create {s}: {any}\n", .{ save_bin, err });
            return;
        };
        defer file_bin.close();

        var file_minisig = std.fs.createFileAbsolute(save_bin_minisig, .{}) catch |err| {
            std.debug.print("\nFailed to create {s}: {any}\n", .{ save_bin, err });
            return;
        };
        defer file_minisig.close();

        var file_pub = std.fs.createFileAbsolute(save_minisig_pub, .{}) catch |err| {
            std.debug.print("\nFailed to create {s}: {any}\n", .{ save_bin, err });
            return;
        };
        defer file_pub.close();

        fetch.fetch_file(url_bin_z, &file_bin) catch |err| {
            std.debug.print("\r\x1b[2Kfailed: {s} -- {any}\n", .{ name, err });
            std.process.exit(1);
        };
        fetch.fetch_file(url_bin_minisig_z, &file_minisig) catch |err| {
            std.debug.print("\r\x1b[2Kfailed: {s} -- {any}\n", .{ name, err });
            std.process.exit(1);
        };
        fetch.fetch_file(url_minisig_pub_z, &file_pub) catch |err| {
            std.debug.print("\r\x1b[2Kfailed: {s} -- {any}\n", .{ name, err });
            std.process.exit(1);
        };
}

pub fn check_minisign(alc: std.mem.Allocator, name: []const u8) !void {
    const savedir = try std.fmt.allocPrint(alc, "{s}/{s}", .{ constants.hclos_repos, name });
    defer alc.free(savedir);
    
    const bin = try std.fmt.allocPrint(alc, "{s}/index.bin", .{savedir});
    defer alc.free(bin);
    
    const bin_minisig = try std.fmt.allocPrint(alc, "{s}/index.bin.minisig", .{savedir});
    defer alc.free(bin_minisig);
    
    const pub_minisig = try std.fmt.allocPrint(alc, "{s}/{s}.pub", .{ savedir, name });
    defer alc.free(pub_minisig);

    const args = &[_][]const u8{
        "-Vm", bin, "-p", pub_minisig, "-x", bin_minisig,
    };
    const result = try minisign.exec_minisign(alc, true, name, args[0..]);
    if (!result) {
        try std.fs.deleteTreeAbsolute(savedir);
    }
}

fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn is_root() bool {
    return std.os.linux.getuid() == 0;
}
