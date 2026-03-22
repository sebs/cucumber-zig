const std = @import("std");
const types = @import("../types.zig");
const MessagesFormatter = @import("messages.zig");

test "messages formatter emits NDJSON for test run lifecycle" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var msgs = MessagesFormatter.init(writer);
    var fmt = msgs.formatter();

    const pickle = types.Pickle{
        .id = "pickle-1",
        .name = "Add numbers",
        .uri = "features/math.feature",
        .line = 5,
        .steps = &.{
            .{ .text = "I have 5", .keyword = "Given ", .id = "step-1" },
            .{ .text = "I add 3", .keyword = "When ", .id = "step-2" },
        },
        .tags = &.{},
    };

    fmt.onTestRunStarted();
    fmt.onTestCaseStarted(.{ .pickle = pickle });
    fmt.onTestStepStarted(pickle, 0);
    fmt.onTestStepFinished(pickle, 0, .{
        .status = .passed,
        .duration_ns = 1_000_000,
        .step_keyword = "Given ",
        .step_text = "I have 5",
    });
    fmt.onTestStepStarted(pickle, 1);
    fmt.onTestStepFinished(pickle, 1, .{
        .status = .passed,
        .duration_ns = 2_000_000,
        .step_keyword = "When ",
        .step_text = "I add 3",
    });
    fmt.onTestCaseFinished(.{
        .pickle = pickle,
        .step_results = &.{},
        .status = .passed,
        .duration_ns = 3_000_000,
    });
    fmt.onTestRunFinished(.{
        .total = 1,
        .passed = 1,
        .duration_ns = 3_000_000,
    });

    const output = fbs.getWritten();

    // Each line should be valid JSON
    var line_iter = std.mem.splitScalar(u8, output, '\n');
    var line_count: usize = 0;
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, line, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value == .object);
        line_count += 1;
    }

    // Should have 7 messages: runStarted, caseStarted, 2x stepStarted, 2x stepFinished, caseFinished, runFinished
    try std.testing.expectEqual(@as(usize, 8), line_count);
}

test "messages formatter includes testRunStarted" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var msgs = MessagesFormatter.init(writer);
    msgs.onTestRunStarted();

    const output = fbs.getWritten();
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value.object.get("testRunStarted") != null);
}

test "messages formatter includes error message in step finished" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var msgs = MessagesFormatter.init(writer);

    const pickle = types.Pickle{
        .id = "p1",
        .name = "Fail",
        .uri = "test.feature",
        .line = 1,
        .steps = &.{.{ .text = "it fails", .keyword = "Then ", .id = "s1" }},
        .tags = &.{},
    };

    msgs.onTestStepFinished(pickle, 0, .{
        .status = .failed,
        .step_keyword = "Then ",
        .step_text = "it fails",
        .err_message = "expected true",
        .duration_ns = 500,
    });

    const output = fbs.getWritten();
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output, .{});
    defer parsed.deinit();

    const step_finished = parsed.value.object.get("testStepFinished").?.object;
    try std.testing.expectEqualStrings("failed", step_finished.get("status").?.string);
    try std.testing.expectEqualStrings("expected true", step_finished.get("errorMessage").?.string);
    try std.testing.expectEqual(@as(i64, 500), step_finished.get("duration").?.integer);
}

test "messages formatter testRunFinished includes success flag" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var msgs = MessagesFormatter.init(writer);

    msgs.onTestRunFinished(.{
        .total = 5,
        .passed = 4,
        .failed = 1,
        .duration_ns = 10_000_000,
    });

    const output = fbs.getWritten();
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output, .{});
    defer parsed.deinit();

    const run_finished = parsed.value.object.get("testRunFinished").?.object;
    try std.testing.expect(run_finished.get("success").? == .bool);
    try std.testing.expect(!run_finished.get("success").?.bool);

    // Test with all passed
    var buf2: [4096]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(&buf2);
    var msgs2 = MessagesFormatter.init(fbs2.writer().any());
    msgs2.onTestRunFinished(.{ .total = 3, .passed = 3, .duration_ns = 0 });

    const output2 = fbs2.getWritten();
    const parsed2 = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output2, .{});
    defer parsed2.deinit();
    try std.testing.expect(parsed2.value.object.get("testRunFinished").?.object.get("success").?.bool);
}
