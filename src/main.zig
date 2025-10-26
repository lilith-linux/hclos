const std = @import("std");
const eql = std.mem.eql;

const update = @import("update");
const install = @import("install");

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
        try install.install(args[2..]);
    } else if (eql(u8, args[1], "update")) {
        try update.update_repo();
    } else if (eql(u8, args[1], "remove")) {} else if (eql(u8, args[1], "search")) {} else if (eql(u8, args[1], "list")) {} else if (eql(u8, args[1], "info")) {} else if (eql(u8, args[1], "clean")) {} else if (eql(u8, args[1], "version")) {} else {
        try display_help();
        return;
    }
    return;
}

fn display_help() !void {
    std.debug.print("{s}\n", .{help_message});
}
