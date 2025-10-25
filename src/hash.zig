const std = @import("std");
const Blake3 = std.crypto.hash.Blake3;

pub fn gen_hash(allocator: std.mem.Allocator, input_file: []const u8) ![]const u8 {
    const file = try std.fs.openFileAbsolute(input_file, .{});
    defer file.close();

    var hasher = Blake3.init(.{});
    var buffer: [1024 * 1024]u8 = undefined;

    while (true) {
        const bytes_read = try file.read(&buffer);
        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
    }

    var hash: [32]u8 = undefined;
    hasher.final(&hash);

    var hex_string = std.ArrayList(u8){};
    defer hex_string.deinit(allocator);

    const writer = hex_string.writer(allocator);
    for (hash) |byte| {
        try writer.print("{x:0>2}", .{byte});
    }
    const hash_hex = try allocator.dupe(u8, hex_string.items);

    return hash_hex;
}
