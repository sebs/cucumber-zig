const std = @import("std");
const types = @import("../types.zig");
const JsonFormatter = @import("json.zig");

test "json formatter produces valid JSON array" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var json_fmt = JsonFormatter.init(std.testing.allocator, writer);
    defer json_fmt.deinit();

    var fmt = json_fmt.formatter();

    const step_results = [_]types.StepResult{
        .{ .status = .passed, .step_keyword = "Given ", .step_text = "I have a value", .duration_ns = 100_000 },
        .{ .status = .passed, .step_keyword = "Then ", .step_text = "it works", .duration_ns = 200_000 },
    };

    fmt.onTestCaseFinished(.{
        .pickle = .{
            .id = "1",
            .name = "Simple test",
            .uri = "features/simple.feature",
            .line = 3,
            .steps = &.{},
            .tags = &.{},
        },
        .step_results = &step_results,
        .status = .passed,
        .duration_ns = 300_000,
    });

    fmt.onTestRunFinished(.{ .total = 1, .passed = 1, .duration_ns = 300_000 });

    const output = fbs.getWritten();

    // Validate it parses as JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output, .{});
    defer parsed.deinit();

    const root = parsed.value;
    try std.testing.expect(root == .array);
    try std.testing.expectEqual(@as(usize, 1), root.array.items.len);

    const feature = root.array.items[0];
    try std.testing.expect(feature == .object);

    const uri = feature.object.get("uri").?;
    try std.testing.expectEqualStrings("features/simple.feature", uri.string);

    const elements = feature.object.get("elements").?.array;
    try std.testing.expectEqual(@as(usize, 1), elements.items.len);

    const scenario = elements.items[0];
    try std.testing.expectEqualStrings("Simple test", scenario.object.get("name").?.string);

    const steps = scenario.object.get("steps").?.array;
    try std.testing.expectEqual(@as(usize, 2), steps.items.len);

    const step0 = steps.items[0].object;
    try std.testing.expectEqualStrings("Given ", step0.get("keyword").?.string);
    try std.testing.expectEqualStrings("passed", step0.get("result").?.object.get("status").?.string);
}

test "json formatter escapes special characters" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var json_fmt = JsonFormatter.init(std.testing.allocator, writer);
    defer json_fmt.deinit();

    const step_results = [_]types.StepResult{
        .{
            .status = .failed,
            .step_keyword = "Then ",
            .step_text = "it says \"hello\"",
            .err_message = "line1\nline2",
        },
    };

    json_fmt.onTestCaseFinished(.{
        .pickle = .{
            .id = "1",
            .name = "Escape test",
            .uri = "test.feature",
            .line = 1,
            .steps = &.{},
            .tags = &.{},
        },
        .step_results = &step_results,
        .status = .failed,
        .duration_ns = 0,
    });
    json_fmt.onTestRunFinished(.{ .total = 1, .failed = 1 });

    const output = fbs.getWritten();
    // Should parse without error
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output, .{});
    defer parsed.deinit();

    // Verify the escaped strings round-trip correctly
    const steps = parsed.value.array.items[0].object.get("elements").?.array.items[0].object.get("steps").?.array;
    const step = steps.items[0].object;
    try std.testing.expectEqualStrings("it says \"hello\"", step.get("name").?.string);
    try std.testing.expectEqualStrings("line1\nline2", step.get("result").?.object.get("error_message").?.string);
}

test "json formatter groups scenarios by feature URI" {
    var buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var json_fmt = JsonFormatter.init(std.testing.allocator, writer);
    defer json_fmt.deinit();

    json_fmt.onTestCaseFinished(.{
        .pickle = .{ .id = "1", .name = "A", .uri = "a.feature", .steps = &.{}, .tags = &.{} },
        .step_results = &.{},
        .status = .passed,
        .duration_ns = 0,
    });
    json_fmt.onTestCaseFinished(.{
        .pickle = .{ .id = "2", .name = "B", .uri = "b.feature", .steps = &.{}, .tags = &.{} },
        .step_results = &.{},
        .status = .passed,
        .duration_ns = 0,
    });
    json_fmt.onTestCaseFinished(.{
        .pickle = .{ .id = "3", .name = "C", .uri = "a.feature", .steps = &.{}, .tags = &.{} },
        .step_results = &.{},
        .status = .passed,
        .duration_ns = 0,
    });

    json_fmt.onTestRunFinished(.{ .total = 3, .passed = 3 });

    const output = fbs.getWritten();
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output, .{});
    defer parsed.deinit();

    // Should have 2 features
    try std.testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);

    // a.feature should have 2 elements
    var found_a = false;
    for (parsed.value.array.items) |feature| {
        const uri = feature.object.get("uri").?.string;
        if (std.mem.eql(u8, uri, "a.feature")) {
            try std.testing.expectEqual(@as(usize, 2), feature.object.get("elements").?.array.items.len);
            found_a = true;
        }
    }
    try std.testing.expect(found_a);
}

test "json formatter includes tags" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var json_fmt = JsonFormatter.init(std.testing.allocator, writer);
    defer json_fmt.deinit();

    json_fmt.onTestCaseFinished(.{
        .pickle = .{
            .id = "1",
            .name = "Tagged",
            .uri = "test.feature",
            .line = 1,
            .steps = &.{},
            .tags = &.{ .{ .name = "@smoke" }, .{ .name = "@fast" } },
        },
        .step_results = &.{},
        .status = .passed,
        .duration_ns = 0,
    });

    json_fmt.onTestRunFinished(.{ .total = 1, .passed = 1 });

    const output = fbs.getWritten();
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output, .{});
    defer parsed.deinit();

    const tags = parsed.value.array.items[0].object.get("elements").?.array.items[0].object.get("tags").?.array;
    try std.testing.expectEqual(@as(usize, 2), tags.items.len);
    try std.testing.expectEqualStrings("@smoke", tags.items[0].object.get("name").?.string);
    try std.testing.expectEqualStrings("@fast", tags.items[1].object.get("name").?.string);
}
