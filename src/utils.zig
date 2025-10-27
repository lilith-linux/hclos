const std = @import("std");

pub fn makeDirAbsoluteRecursive(allocator: std.mem.Allocator, dir_path: []const u8) !void {
    var parts = std.mem.splitSequence(u8, dir_path, "/");
    var current_path = std.ArrayList(u8){};
    defer current_path.deinit(allocator);

    if (dir_path.len > 0 and dir_path[0] == '/') {
        try current_path.append(allocator, '/');
    }

    while (parts.next()) |part| {
        if (part.len == 0) continue;

        if (current_path.items.len > 1) {
            try current_path.append(allocator, '/');
        }
        try current_path.appendSlice(allocator, part);

        std.fs.makeDirAbsolute(current_path.items) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };
    }
}
