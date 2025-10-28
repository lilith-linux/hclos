const std = @import("std");
const linux = std.os.linux;

pub const ChrootEnv = struct {
    root: []const u8,
    allocator: std.mem.Allocator,
    mounted: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, root: []const u8) !ChrootEnv {
        const root_full = try std.fs.realpathAlloc(allocator, root);

        return ChrootEnv{
            .root = root_full,
            .allocator = allocator,
            .mounted = std.ArrayList([]const u8){},
        };
    }

    pub fn deinit(self: *ChrootEnv) void {
        self.allocator.free(self.root);
        for (self.mounted.items) |path| {
            self.allocator.free(path);
        }
        self.mounted.deinit(self.allocator);
    }

    /// 必要なディレクトリを作成してマウント
    pub fn setup(self: *ChrootEnv) !void {
        // Mount Namespaceを新規作成
        const unshare_result = linux.unshare(linux.CLONE.NEWNS);
        if (unshare_result != 0) {
            std.debug.print("Failed to unshare mount namespace: {}\n", .{std.posix.errno(unshare_result)});
            return error.UnshareFailed;
        }

        // 現在のマウントをprivateにする（重要！これによりホストに影響しなくなる）
        try self.makePrivate();

        // 必要なディレクトリを作成
        try self.createDirs();

        // 仮想ファイルシステムをマウント
        try self.mountProc();
        try self.mountSys();
        // try self.mountDev();
        // try self.mountDevPts();
        try self.mountTmp();
    }

    /// 現在のマウントをprivateにする
    fn makePrivate(self: *ChrootEnv) !void {
        _ = self;
        const root = try std.posix.toPosixPath("/");
        const result = linux.mount(null, &root, null, linux.MS.PRIVATE | linux.MS.REC, 0);
        if (std.posix.errno(result) != .SUCCESS) {
            std.debug.print("Failed to make mounts private: {}\n", .{std.posix.errno(result)});
            return error.MakePrivateFailed;
        }
    }

    /// 必要なディレクトリを作成
    fn createDirs(self: *ChrootEnv) !void {
        const dirs = [_][]const u8{
            "/proc",
            "/sys",
            "/tmp",
            "/run",
        };

        for (dirs) |dir| {
            const full_path = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.root, dir });
            defer self.allocator.free(full_path);

            std.fs.makeDirAbsolute(full_path) catch |err| {
                if (err != error.PathAlreadyExists) {
                    return err;
                }
            };
        }
    }

    /// /proc をマウント
    fn mountProc(self: *ChrootEnv) !void {
        const target = try std.fmt.allocPrint(self.allocator, "{s}/proc", .{self.root});
        errdefer self.allocator.free(target);

        try self.mount("proc", target, "proc", linux.MS.NOSUID | linux.MS.NOEXEC | linux.MS.NODEV, null);
        try self.mounted.append(self.allocator, target);
    }

    /// /sys をマウント
    fn mountSys(self: *ChrootEnv) !void {
        const target = try std.fmt.allocPrint(self.allocator, "{s}/sys", .{self.root});
        errdefer self.allocator.free(target);

        try self.mount("sysfs", target, "sysfs", linux.MS.NOSUID | linux.MS.NOEXEC | linux.MS.NODEV | linux.MS.RDONLY, null);
        try self.mounted.append(self.allocator, target);
    }

    /// /dev をマウント (bind mount)
    // fn mountDev(self: *ChrootEnv) !void {
    //     const target = try std.fmt.allocPrint(self.allocator, "{s}/dev", .{self.root});
    //     errdefer self.allocator.free(target);

    //     try self.mount("/dev", target, null, linux.MS.BIND | linux.MS.REC, null);
    //     try self.mounted.append(self.allocator, target);
    // }

    /// /dev/pts をマウント
    // fn mountDevPts(self: *ChrootEnv) !void {
    //     const target = try std.fmt.allocPrint(self.allocator, "{s}/dev/pts", .{self.root});
    //     errdefer self.allocator.free(target);

    //     try self.mount("devpts", target, "devpts", linux.MS.NOSUID | linux.MS.NOEXEC, "mode=0620,ptmxmode=0666");
    //     try self.mounted.append(self.allocator, target);
    // }

    /// /tmp をマウント (tmpfs)
    fn mountTmp(self: *ChrootEnv) !void {
        const target = try std.fmt.allocPrint(self.allocator, "{s}/tmp", .{self.root});
        errdefer self.allocator.free(target);

        try self.mount("tmpfs", target, "tmpfs", linux.MS.NOSUID | linux.MS.NODEV, "mode=1777");
        try self.mounted.append(self.allocator, target);
    }

    /// マウント操作のラッパー
    fn mount(
        self: *ChrootEnv,
        source: []const u8,
        target: []const u8,
        fstype: ?[]const u8,
        flags: u32,
        data: ?[]const u8,
    ) !void {
        _ = self;

        const c_source = try std.posix.toPosixPath(source);
        const c_target = try std.posix.toPosixPath(target);

        var c_fstype: ?[*:0]const u8 = null;
        if (fstype) |fs| {
            const fs_path = try std.posix.toPosixPath(fs);
            c_fstype = &fs_path;
        }

        var c_data: ?[*:0]const u8 = null;
        if (data) |d| {
            const data_path = try std.posix.toPosixPath(d);
            c_data = &data_path;
        }

        const result = linux.mount(&c_source, &c_target, c_fstype, flags, @intFromPtr(c_data));
        if (std.posix.errno(result) != .SUCCESS) {
            std.debug.print("Mount failed: {s} -> {s} (errno: {})\n", .{ source, target, std.posix.errno(result) });
            return error.MountFailed;
        }
    }

    /// chrootを実行
    pub fn enterChroot(self: *ChrootEnv) !void {
        const c_path = try std.posix.toPosixPath(self.root);

        // 1. 新しいルートに移動
        const chdir_result = linux.chdir(&c_path);
        if (chdir_result != 0) {
            return error.ChdirFailed;
        }

        // 2. chroot実行
        const chroot_result = linux.chroot(&c_path);
        if (chroot_result != 0) {
            return error.ChrootFailed;
        }

        // 3. カレントディレクトリを / に設定
        const root_path = try std.posix.toPosixPath("/");
        const final_chdir = linux.chdir(&root_path);
        if (final_chdir != 0) {
            return error.FinalChdirFailed;
        }
    }

    /// クリーンアップ (マウントを解除)
    pub fn cleanup(self: *ChrootEnv) void {
        // 逆順でアンマウント
        var i: usize = self.mounted.items.len;
        while (i > 0) {
            i -= 1;
            const path = self.mounted.items[i];

            self.umount(path) catch |err| {
                std.debug.print("Warning: Failed to unmount {s}: {}\n", .{ path, err });
            };
        }
    }

    /// アンマウント
    fn umount(self: *ChrootEnv, target: []const u8) !void {
        _ = self;
        const c_target = try std.posix.toPosixPath(target);

        // MNT.DETACHを使ってlazy unmount
        const result = linux.umount2(&c_target, linux.MNT.DETACH);
        if (std.posix.errno(result) != .SUCCESS) {
            const err = std.posix.errno(result);
            // EINVALやENOENTは無視（既にアンマウントされている可能性）
            if (err != .INVAL and err != .NOENT) {
                std.debug.print("Unmount failed for {s}: {}\n", .{ target, err });
                return error.UmountFailed;
            }
        }
    }
};
