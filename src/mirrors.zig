const std = @import("std");
const toml = @import("toml");
const constants = @import("constants.zig");

pub const Mirrors = struct {
    mirror: [][]const u8,
};

pub fn parse_mirrors(allocator: std.mem.Allocator) !Mirrors {
    var parser = toml.Parser(Mirrors).init(allocator);
    defer parser.deinit();

    var result = try parser.parseFile(constants.hclos_mirrors);
    defer result.deinit();

    return result.value;
}
