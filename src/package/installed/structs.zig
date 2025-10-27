const std = @import("std");

pub const InstalledPackage = struct {
    name: []const u8,
    version: []const u8,
    pathlist: [][]const u8,
};

pub const InstalledPackageList = struct {
    packages: []InstalledPackage,
};
