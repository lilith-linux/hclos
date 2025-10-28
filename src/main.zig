const std = @import("std");
const eql = std.mem.eql;

const update = @import("update");
const install = @import("install");
const search = @import("search");

const help_message = @embedFile("./templates/help_message");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);

    if (args.len < 2) {
        try display_help();
        std.process.exit(1);
    }

    if (eql(u8, args[1], "install")) {
        if (args.len < 3) {
            try display_help();
            std.process.exit(1);
        }

        if (std.mem.eql(u8, args[2], "--prefix")) {
            if (args.len < 5) {
                std.debug.print("usage: --prefix <rootdir> [PACKAGES...]\n", .{});
                std.process.exit(1);
            }

            try install.install(allocator, args[4..], .{ .prefix = args[3] });
        } else {
            try install.install(allocator, args[2..], .{});
        }
    } else if (eql(u8, args[1], "update")) {
        if (args.len == 3 and std.mem.eql(u8, args[2], "--prefix")) {
            std.debug.print("usage: update [--prefix <rootdir>]\n", .{});
            std.process.exit(1);
        } else if (args.len == 4 and std.mem.eql(u8, args[2], "--prefix")) {
            try update.update_repo(allocator, .{ .prefix = args[3] });
        } else {
            try update.update_repo(allocator, .{});
        }
    } else if (eql(u8, args[1], "remove")) {} else if (eql(u8, args[1], "search")) {
        if (args.len < 3) {
            try display_help();
            std.process.exit(1);
        }

        try search.search(allocator, args[2..]);
    } else if (eql(u8, args[1], "list")) {} else if (eql(u8, args[1], "info")) {} else if (eql(u8, args[1], "clean")) {} else if (eql(u8, args[1], "version")) {} else {
        std.debug.print("unknown command: {s}\n", .{args[1]});
        try display_help();
        return;
    }
    return;
}

fn display_help() !void {
    std.debug.print("{s}\n", .{help_message});
}
