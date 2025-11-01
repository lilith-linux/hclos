const std = @import("std");

const MAX_PACKAGES = 800;

pub const Packages = struct {
    package: [MAX_PACKAGES]Package,
};

pub const Package = struct {
    name: [32]u8,
    depend: [64][32]u8,
    description: [124]u8,
    version: [32]u8,
    license: [32]u8,
    isbuild: bool,
    src_url: [2083]u8,
};

pub const SearchResult = struct {
    package: *const Package,
    index: usize,
    relevance: u32,
};

pub const PackageDB = struct {
    list: *const Packages,
    exact_map: std.StringHashMap(usize),
    prefix_index: std.ArrayList(PrefixEntry),
    trigram_index: std.StringHashMap(std.ArrayList(usize)),
    allocator: std.mem.Allocator,

    const PrefixEntry = struct {
        name: []const u8,
        index: usize,
    };

    pub fn init(allocator: std.mem.Allocator, list: *const Packages) !PackageDB {
        var exact_map = std.StringHashMap(usize).init(allocator);
        var prefix_index = std.ArrayList(PrefixEntry){};
        var trigram_index = std.StringHashMap(std.ArrayList(usize)).init(allocator);

        for (&list.package, 0..) |*pkg, i| {
            const end = std.mem.indexOfScalar(u8, &pkg.name, 0) orelse pkg.name.len;
            const key = pkg.name[0..end];
            if (key.len == 0) continue;

            try exact_map.put(key, i);

            try prefix_index.append(allocator, .{ .name = key, .index = i });

            try indexTrigrams(allocator, key, i, &trigram_index);
        }

        std.mem.sort(PrefixEntry, prefix_index.items, {}, comparePrefix);

        return PackageDB{
            .list = list,
            .exact_map = exact_map,
            .prefix_index = prefix_index,
            .trigram_index = trigram_index,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PackageDB) void {
        self.exact_map.deinit();
        self.prefix_index.deinit(self.allocator);

        var iter = self.trigram_index.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.trigram_index.deinit();
    }

    pub fn find(self: *const PackageDB, name: []const u8) ?*const Package {
        if (self.exact_map.get(name)) |idx| {
            return &self.list.package[idx];
        }
        return null;
    }

    // Alias: Exact match search
    pub fn findExact(self: *const PackageDB, name: []const u8) ?*const Package {
        return self.find(name);
    }

    // Prefix search (O(log n + k) - fast)
    // Example: query="vim" → ["vim", "vim-plugin", "vimrc"]
    pub fn findByPrefix(self: *const PackageDB, allocator: std.mem.Allocator, prefix: []const u8) !std.ArrayList(SearchResult) {
        var results = std.ArrayList(SearchResult){};

        var left: usize = 0;
        var right: usize = self.prefix_index.items.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const entry = self.prefix_index.items[mid];

            if (std.mem.lessThan(u8, entry.name, prefix)) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        var pos = left;
        while (pos < self.prefix_index.items.len) : (pos += 1) {
            const entry = self.prefix_index.items[pos];

            if (!std.mem.startsWith(u8, entry.name, prefix)) break;

            try results.append(allocator, .{
                .package = &self.list.package[entry.index],
                .index = entry.index,
                .relevance = if (std.mem.eql(u8, entry.name, prefix)) 100 else 50,
            });
        }

        return results;
    }

    // Fuzzy search using Levenshtein distance
    // Example: query="vim" → ["vim", "neovim", "gvim"]
    pub fn search(self: *const PackageDB, allocator: std.mem.Allocator, query: []const u8) !std.ArrayList(SearchResult) {
        if (query.len == 0) return std.ArrayList(SearchResult){};

        if (self.find(query)) |pkg| {
            var results = std.ArrayList(SearchResult){};
            const idx = self.exact_map.get(query).?;
            try results.append(allocator, .{
                .package = pkg,
                .index = idx,
                .relevance = 100,
            });
            return results;
        }

        var candidate_scores = std.AutoHashMap(usize, u32).init(allocator);
        defer candidate_scores.deinit();

        var trigrams = try generateTrigrams(allocator, query);
        defer {
            for (trigrams.items) |tri| {
                allocator.free(tri);
            }
            trigrams.deinit(allocator);
        }

        for (trigrams.items) |tri| {
            if (self.trigram_index.get(tri)) |indices| {
                for (indices.items) |idx| {
                    const gop = try candidate_scores.getOrPut(idx);
                    if (gop.found_existing) {
                        gop.value_ptr.* += 10;
                    } else {
                        gop.value_ptr.* = 10;
                    }
                }
            }
        }

        var results = std.ArrayList(SearchResult){};
        var iter = candidate_scores.iterator();
        while (iter.next()) |entry| {
            const idx = entry.key_ptr.*;
            const pkg = &self.list.package[idx];
            const end = std.mem.indexOfScalar(u8, &pkg.name, 0) orelse pkg.name.len;
            const name = pkg.name[0..end];

            const relevance = entry.value_ptr.*;
            if (std.mem.startsWith(u8, name, query)) {}
            if (std.mem.indexOf(u8, name, query) != null) {}

            try results.append(allocator, .{
                .package = pkg,
                .index = idx,
                .relevance = relevance,
            });
        }

        std.mem.sort(SearchResult, results.items, {}, compareRelevance);

        return results;
    }

    // Contains description search
    pub fn searchWithDescription(self: *const PackageDB, allocator: std.mem.Allocator, query: []const u8) !std.ArrayList(SearchResult) {
        var results = try self.search(allocator, query);

        const query_lower = try std.ascii.allocLowerString(allocator, query);
        defer allocator.free(query_lower);

        for (&self.list.package, 0..) |*pkg, i| {
            const name_end = std.mem.indexOfScalar(u8, &pkg.name, 0) orelse pkg.name.len;
            if (name_end == 0) continue;

            const desc_end = std.mem.indexOfScalar(u8, &pkg.description, 0) orelse pkg.description.len;
            const desc = pkg.description[0..desc_end];

            if (desc.len > 0) {
                const desc_lower = try std.ascii.allocLowerString(allocator, desc);
                defer allocator.free(desc_lower);

                if (std.mem.indexOf(u8, desc_lower, query_lower) != null) {
                    var already_exists = false;
                    for (results.items) |res| {
                        if (res.index == i) {
                            already_exists = true;
                            break;
                        }
                    }

                    if (!already_exists) {
                        try results.append(allocator, .{
                            .package = pkg,
                            .index = i,
                        });
                    }
                }
            }
        }

        std.mem.sort(SearchResult, results.items, {}, compareRelevance);

        return results;
    }

    pub fn listPackages(self: *const PackageDB, allocator: std.mem.Allocator) !std.ArrayList(*const Package) {
        var result = std.ArrayList(*const Package){};

        for (&self.list.package) |*pkg| {
            const end = std.mem.indexOfScalar(u8, &pkg.name, 0) orelse pkg.name.len;
            if (end == 0) continue;

            try result.append(allocator, pkg);
        }

        return result;
    }

    pub fn listSorted(self: *const PackageDB, allocator: std.mem.Allocator) !std.ArrayList(*const Package) {
        const result = try self.listPackages(allocator);
        std.mem.sort(*const Package, result.items, {}, comparePackageName);
        return result;
    }

    fn indexTrigrams(
        allocator: std.mem.Allocator,
        name: []const u8,
        index: usize,
        trigram_index: *std.StringHashMap(std.ArrayList(usize)),
    ) !void {
        var trigrams = try generateTrigrams(allocator, name);
        defer {
            for (trigrams.items) |tri| {
                allocator.free(tri);
            }
            trigrams.deinit(allocator);
        }

        for (trigrams.items) |tri| {
            const gop = try trigram_index.getOrPut(tri);
            if (!gop.found_existing) {
                gop.key_ptr.* = try allocator.dupe(u8, tri);
                gop.value_ptr.* = std.ArrayList(usize){};
            }
            try gop.value_ptr.append(allocator, index);
        }
    }

    fn generateTrigrams(allocator: std.mem.Allocator, text: []const u8) !std.ArrayList([]const u8) {
        var trigrams = std.ArrayList([]const u8){};

        if (text.len < 3) {
            try trigrams.append(allocator, try allocator.dupe(u8, text));
            return trigrams;
        }

        var seen = std.StringHashMap(void).init(allocator);
        defer seen.deinit();

        var i: usize = 0;
        while (i + 3 <= text.len) : (i += 1) {
            const tri = text[i .. i + 3];
            if (!seen.contains(tri)) {
                try trigrams.append(allocator, try allocator.dupe(u8, tri));
                try seen.put(tri, {});
            }
        }

        return trigrams;
    }

    fn comparePrefix(_: void, a: PrefixEntry, b: PrefixEntry) bool {
        return std.mem.lessThan(u8, a.name, b.name);
    }

    fn compareRelevance(_: void, a: SearchResult, b: SearchResult) bool {
        return a.relevance > b.relevance;
    }
    fn comparePackageName(_: void, a: *const Package, b: *const Package) bool {
        const a_end = std.mem.indexOfScalar(u8, &a.name, 0) orelse a.name.len;
        const b_end = std.mem.indexOfScalar(u8, &b.name, 0) orelse b.name.len;
        return std.mem.lessThan(u8, a.name[0..a_end], b.name[0..b_end]);
    }
};
