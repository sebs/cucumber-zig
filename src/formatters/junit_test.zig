const std = @import("std");
const types = @import("../types.zig");
const JunitFormatter = @import("junit.zig");

test "junit formatter produces valid XML structure" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var junit = JunitFormatter.init(std.testing.allocator, writer);
    defer junit.deinit();

    var fmt = junit.formatter();

    const step_results = [_]types.StepResult{
        .{ .status = .passed, .step_keyword = "Given ", .step_text = "a value", .duration_ns = 100_000 },
        .{ .status = .passed, .step_keyword = "Then ", .step_text = "it works", .duration_ns = 200_000 },
    };

    fmt.onTestCaseFinished(.{
        .pickle = .{
            .id = "1",
            .name = "Simple scenario",
            .uri = "features/simple.feature",
            .line = 3,
            .steps = &.{},
            .tags = &.{},
        },
        .step_results = &step_results,
        .status = .passed,
        .duration_ns = 300_000,
    });

    fmt.onTestRunFinished(.{
        .total = 1,
        .passed = 1,
        .duration_ns = 300_000,
    });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "<?xml version=\"1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "<testsuites") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "<testsuite name=\"features/simple.feature\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "<testcase name=\"Simple scenario\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "</testsuites>") != null);
}

test "junit formatter includes failure elements" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var junit = JunitFormatter.init(std.testing.allocator, writer);
    defer junit.deinit();

    const step_results = [_]types.StepResult{
        .{ .status = .passed, .step_keyword = "Given ", .step_text = "a value" },
        .{ .status = .failed, .step_keyword = "Then ", .step_text = "it fails", .err_message = "assertion failed" },
    };

    junit.onTestCaseFinished(.{
        .pickle = .{
            .id = "2",
            .name = "Failing scenario",
            .uri = "features/fail.feature",
            .line = 5,
            .steps = &.{},
            .tags = &.{},
        },
        .step_results = &step_results,
        .status = .failed,
        .duration_ns = 500_000,
    });

    junit.onTestRunFinished(.{
        .total = 1,
        .failed = 1,
        .duration_ns = 500_000,
    });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "<failure") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "assertion failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "failures=\"1\"") != null);
}

test "junit formatter includes skipped elements" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var junit = JunitFormatter.init(std.testing.allocator, writer);
    defer junit.deinit();

    junit.onTestCaseFinished(.{
        .pickle = .{
            .id = "3",
            .name = "Skipped scenario",
            .uri = "features/skip.feature",
            .line = 1,
            .steps = &.{},
            .tags = &.{},
        },
        .step_results = &.{},
        .status = .skipped,
        .duration_ns = 0,
    });

    junit.onTestRunFinished(.{
        .total = 1,
        .skipped = 1,
        .duration_ns = 0,
    });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "<skipped/>") != null);
}

test "junit formatter groups by feature URI" {
    var buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var junit = JunitFormatter.init(std.testing.allocator, writer);
    defer junit.deinit();

    junit.onTestCaseFinished(.{
        .pickle = .{ .id = "1", .name = "A", .uri = "a.feature", .steps = &.{}, .tags = &.{} },
        .step_results = &.{},
        .status = .passed,
        .duration_ns = 0,
    });
    junit.onTestCaseFinished(.{
        .pickle = .{ .id = "2", .name = "B", .uri = "b.feature", .steps = &.{}, .tags = &.{} },
        .step_results = &.{},
        .status = .passed,
        .duration_ns = 0,
    });
    junit.onTestCaseFinished(.{
        .pickle = .{ .id = "3", .name = "C", .uri = "a.feature", .steps = &.{}, .tags = &.{} },
        .step_results = &.{},
        .status = .passed,
        .duration_ns = 0,
    });

    junit.onTestRunFinished(.{ .total = 3, .passed = 3 });

    const output = fbs.getWritten();
    // Should have exactly 2 testsuites (a.feature and b.feature)
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, output, "<testsuite name="));
}
