const std = @import("std");
const linux = std.os.linux;
const chroot = @import("chroot.zig");
const utils = @import("utils");

pub fn pre_install(allocator: std.mem.Allocator, file_path: []const u8, prefix: []const u8, is_prefix: bool) !void {
    if (is_prefix) {
        var env = try chroot.ChrootEnv.init(allocator, prefix);
        defer {
            env.deinit();
        }

        try env.setup();
        defer env.cleanup();

        const pid = try std.posix.fork();

        const target = try std.fmt.allocPrint(allocator, "{s}/script", .{prefix});
        defer allocator.free(target);

        try utils.copyFile(allocator, file_path, target);
        defer utils.deleteFile(target);

        if (pid == 0) {
            try env.enterChroot();
            try real_postinst(allocator, "/script");
            std.posix.exit(0);
        } else {
            const result = std.posix.waitpid(pid, 0);

            if (!std.posix.W.IFEXITED(result.status)) {
                return error.ChildProcessCrashed;
            }
            if (std.posix.W.EXITSTATUS(result.status) != 0) {
                return error.ProcessFailed;
            }
            return;
        }
    } else {
        try real_preinst(allocator, file_path);
    }
}

pub fn post_install(allocator: std.mem.Allocator, file_path: []const u8, prefix: []const u8, is_prefix: bool) !void {
    if (is_prefix) {
        var env = try chroot.ChrootEnv.init(allocator, prefix);
        defer {
            env.deinit();
        }

        try env.setup();
        defer env.cleanup();

        const pid = try std.posix.fork();

        const target = try std.fmt.allocPrint(allocator, "{s}/script", .{prefix});
        defer allocator.free(target);

        try utils.copyFile(allocator, file_path, target);
        defer utils.deleteFile(target);

        if (pid == 0) {
            try env.enterChroot();
            try real_postinst(allocator, "/script");
            std.posix.exit(0);
        } else {
            const result = std.posix.waitpid(pid, 0);

            if (!std.posix.W.IFEXITED(result.status)) {
                return error.ChildProcessCrashed;
            }
            if (std.posix.W.EXITSTATUS(result.status) != 0) {
                return error.ProcessFailed;
            }
            return;
        }
    } else {
        try real_postinst(allocator, file_path);
    }
}

fn real_preinst(allocator: std.mem.Allocator, shfile: []const u8) !void {
    const cmd = try std.fmt.allocPrint(allocator, ". {s} && post_inst", .{shfile});
    defer allocator.free(cmd);

    var child = std.process.Child.init(&.{ "/usr/bin/sh", "-c", cmd }, allocator);

    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.stdin_behavior = .Inherit;

    try child.spawn();
    const status = try child.wait();

    if (status.Exited != 0 or status != .Exited) {
        return error.PreInstallFailed;
    }
}

fn real_postinst(allocator: std.mem.Allocator, shfile: []const u8) !void {
    const cmd = try std.fmt.allocPrint(allocator, ". {s} && post_inst", .{shfile});
    defer allocator.free(cmd);

    var child = std.process.Child.init(&.{ "/usr/bin/sh", "-c", cmd }, allocator);

    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.stdin_behavior = .Inherit;

    try child.spawn();
    const status = try child.wait();

    if (status.Exited != 0 or status != .Exited) {
        return error.PostInstallFailed;
    }
}
