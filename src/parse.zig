const std = @import("std");
const toml = @import("toml");


const Packages = struct {
    package: []const Package,
};

const Package = struct {
    name: []const u8,
    version: []const u8,
    desc: []const u8,
    dependencies: []const Depend,
    license: []const u8,
    author: []const u8,
};

const Depend = struct {
    name: []const u8,
    version: []const u8
};


pub fn parse(file_path: []const u8) !Packages {
    const alc = std.heap.page_allocator;

    var parser = toml.Parser(Packages).init(alc);
    defer parser.deinit();

    var result = try parser.parseFile(file_path);
    defer result.deinit();

    return result.value;
}


