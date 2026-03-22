const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Exported module (for downstream packages that depend on cucumber-zig) ──
    _ = b.addModule("cucumber-zig", .{
        .root_source_file = b.path("src/cucumber.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ── Library artifact ──
    const lib = b.addStaticLibrary(.{
        .name = "cucumber-zig",
        .root_source_file = b.path("src/cucumber.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // ── Unit tests ──
    const tests = b.addTest(.{
        .root_source_file = b.path("src/cucumber.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // ── Example: banking application ──
    const cucumber_mod = b.addModule("cucumber", .{
        .root_source_file = b.path("src/cucumber.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example = b.addExecutable(.{
        .name = "banking-example",
        .root_source_file = b.path("example/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("cucumber", cucumber_mod);
    b.installArtifact(example);

    const run_example = b.addRunArtifact(example);
    run_example.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_example.addArgs(args);
    }
    const run_step = b.step("run", "Run the banking example");
    run_step.dependOn(&run_example.step);
}
