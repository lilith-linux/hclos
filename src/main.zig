const std = @import("std");
const eql = std.mem.eql;

const fetch = @import("fetch");
const repos_conf = @import("repos_conf");
const update = @import("update");
const parse = @import("parse.zig");

const help_message = @embedFile("./templates/help_message");
const bootstrap_message = @embedFile("./templates/bootstrap_message");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);

    if (args.len < 2) {
        if (!std.mem.eql(u8, args[0], "huis-boot")) {
            try display_help();
        } else {
            try bootstrap_help();
        }
        std.process.exit(0);
    }

    if (eql(u8, args[1], "install")) {} else if (eql(u8, args[1], "update")) {
        try update.update_repo();
    } else if (eql(u8, args[1], "remove")) {} else if (eql(u8, args[1], "search")) {} else if (eql(u8, args[1], "list")) {} else if (eql(u8, args[1], "info")) {} else if (eql(u8, args[1], "clean")) {} else if (eql(u8, args[1], "version")) {} else {
        if (!std.mem.eql(u8, args[0], "huis-boot")) {
            try display_help();
        } else {
            try bootstrap_help();
        }
        return;
    }
}

fn display_help() !void {
    std.debug.print("{s}\n", .{help_message});
}

fn bootstrap_help() !void {
    std.debug.print("{s}\n", .{bootstrap_message});
}
