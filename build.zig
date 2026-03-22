const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module
    const cucumber_mod = b.addModule("cucumber-zig", .{
        .root_source_file = b.path("src/cucumber.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Library artifact (for linking)
    const lib = b.addStaticLibrary(.{
        .name = "cucumber-zig",
        .root_source_file = b.path("src/cucumber.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Unit tests
    const tests = b.addTest(.{
        .root_source_file = b.path("src/cucumber.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    _ = cucumber_mod;
}

/// Build step that users add to their own build.zig to run cucumber features.
pub const FeatureStepOptions = struct {
    name: []const u8 = "cucumber",
    step_files: []const []const u8,
    feature_dir: []const u8,
    tags: ?[]const u8 = null,
};
