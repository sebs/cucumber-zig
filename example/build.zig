const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Depend on cucumber-zig from the parent directory
    const cucumber_dep = b.dependency("cucumber_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const cucumber_mod = cucumber_dep.module("cucumber-zig");

    // Build the example executable
    const exe = b.addExecutable(.{
        .name = "banking-example",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("cucumber", cucumber_mod);
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the banking example");
    run_step.dependOn(&run_cmd.step);
}
