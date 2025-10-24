const minisign = @embedFile("./external-bin/bin/minisign");
const std = @import("std");
const constants = @import("constants");


pub fn exec_minisign(alc: std.mem.Allocator, info: bool, name: []const u8, args: []const []const u8) !bool{
    const rand = build_random();
    const minisign_file = try std.fmt.allocPrint(alc, "/tmp/{d}.minisign_file", .{rand});
    defer alc.free(minisign_file);

    var file = try std.fs.createFileAbsolute(minisign_file, .{});
    try file.writeAll(minisign);
    try file.setPermissions(.{ .inner = .{ .mode = 0o755 } });
    file.close();
    defer del_file(minisign_file);

    const exec = try std.mem.concat(alc, []const u8, &[_][]const []const u8 {
        &[_][]const u8{minisign_file},
        args,
    });
    defer alc.free(exec);

    var child = std.process.Child.init(exec, alc);

    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const result = try child.spawnAndWait();

    if (result != .Exited or result.Exited != 0) {
        if (info) {
            std.debug.print("\r\x1b[2KSignature verification failed: {s}\n", .{name});
        }else {
            std.debug.print("\nSignature verification failed: {s}\n", .{name});
        }
        return false;
    }
    return true;
}

fn build_random() u64{
    var seed: [8]u8 = undefined;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch |err| {
        std.debug.print("Failed to get randomSeed: {any}\n", .{err});
        std.process.exit(1);
    };

    var prng = std.Random.DefaultPrng.init(@as(u64, @bitCast(seed)));
    const rand = prng.random();
    return rand.intRangeAtMost(u64, 0, 3999);
}

fn del_file(file: []const u8) void {
    _ = std.fs.deleteFileAbsolute(file) catch |err| {
        std.debug.print("Failed to delete minisign temp file: {any}\n", .{err});
    };
}


