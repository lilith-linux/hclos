const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .musl,
    });
    const optimize = b.standardOptimizeOption(.{});

    // for zig-curl(static linking)
    const dep_curl = b.dependency("curl", .{
        .target = target,
        .optimize = optimize,
    });
    
    // for zig-toml
    const dep_toml = b.dependency("toml", .{
        .target = target,
        .optimize = optimize,
    });

    // ========== MODULES ===========
    const constants = b.addModule("constants", .{
        .root_source_file = b.path("src/constants.zig"),
        .target = target,
    });

    const info = b.addModule("info", .{
        .root_source_file = b.path("src/info.zig"),
        .target = target,
    });

    const minisign = b.addModule("minisign", .{
        .root_source_file = b.path("src/minisign.zig"),
        .target = target,
    });

    const repos_conf = b.addModule("repos_conf", .{
        .root_source_file = b.path("src/repos_conf.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "constants", .module = constants },
        }
    });
    repos_conf.addImport("toml", dep_toml.module("toml"));

    const fetch = b.addModule("fetch", .{
        .root_source_file = b.path("src/net/fetch.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "constants", .module = constants },
        }
    });
    fetch.addImport("curl", dep_curl.module("curl"));

    const update = b.addModule("update", .{
        .root_source_file = b.path("src/update/update.zig"),
        .target = target,
        .link_libc = true,
        .imports = &.{
            .{ .name = "info", .module = info },
            .{ .name = "fetch", .module = fetch },
            .{ .name = "constants", .module = constants },
            .{ .name = "repos_conf", .module = repos_conf },
            .{ .name = "minisign", .module = minisign },
        }
    });


    const exe = b.addExecutable(.{
        .name = "hclos",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fetch", .module = fetch },
                .{ .name = "update", .module = update },
                .{ .name = "constants", .module = constants },
                .{ .name = "info", .module = info },
                .{ .name = "minisign", .module = minisign },
                .{ .name = "repos_conf", .module = repos_conf },
            }
        }),
    });


    // imports
    exe.root_module.addImport("curl", dep_curl.module("curl"));
    exe.root_module.addImport("toml", dep_toml.module("toml"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
