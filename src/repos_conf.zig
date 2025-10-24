const std = @import("std");
const toml = @import("toml");
const constants = @import("constants");

pub const ReposConf = struct {
    repo: []Repository,
};

pub const Repository = struct {
    name: []const u8,
    url: []const u8,
};

pub fn parse_repos(allocator: std.mem.Allocator) !toml.Parsed(ReposConf) {
    var parser = toml.Parser(ReposConf).init(allocator);
    defer parser.deinit();

    const result = try parser.parseFile(constants.hclos_repos_conf);

    return result;
}
