const std = @import("std");

const MAX_PACKAGES = 500;

pub const Packages = struct {
    package: [MAX_PACKAGES]Package,
};

pub const Package = struct {
    name: [32]u8,
    depend: [64][32]u8,
    description: [124]u8,
    version: [12]u8,
    license: [32]u8,
    isbuild: bool,
};

pub const PackageDB = struct {
    list: *const Packages,
    map: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator, list: *const Packages) !PackageDB {
        var map = std.StringHashMap(usize).init(allocator);
        for (&list.package, 0..) |*pkg, i| {
            const end = std.mem.indexOfScalar(u8, &pkg.name, 0) orelse pkg.name.len;
            const key = pkg.name[0..end];
            if (key.len != 0) try map.put(key, i);
        }

        return PackageDB{
            .list = list,
            .map = map,
        };
    }

    pub fn deinit(self: *PackageDB) void {
        self.map.deinit();
    }

    pub fn find(self: *const PackageDB, name: []const u8) ?*const Package {
        if (self.map.get(name)) |idx| {
            return &self.list.package[idx];
        }
        return null;
    }
};
