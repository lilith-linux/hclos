const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .musl,
    });


    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "hclos",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });



    // for zig-curl(static linking)
    const dep_curl = b.dependency("curl", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("curl", dep_curl.module("curl"));
    exe.linkLibC();

    // for zig-toml
    const dep_toml = b.dependency("toml", .{
        .target = target,
        .optimize = optimize,
    });
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
