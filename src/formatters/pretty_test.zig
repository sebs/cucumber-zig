const std = @import("std");
const types = @import("../types.zig");
const PrettyFormatter = @import("pretty.zig");

test "pretty formatter outputs scenario with steps" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var pretty = PrettyFormatter{
        .writer = writer,
        .use_colors = false,
    };
    var fmt = pretty.formatter();

    const pickle = types.Pickle{
        .id = "1",
        .name = "Adding numbers",
        .uri = "features/math.feature",
        .line = 3,
        .steps = &.{
            .{ .text = "I have 5", .keyword = "Given " },
            .{ .text = "I add 3", .keyword = "When " },
            .{ .text = "I get 8", .keyword = "Then " },
        },
        .tags = &.{},
    };

    fmt.onTestRunStarted();
    fmt.onTestCaseStarted(.{ .pickle = pickle });

    fmt.onTestStepFinished(pickle, 0, .{
        .status = .passed,
        .step_keyword = "Given ",
        .step_text = "I have 5",
    });
    fmt.onTestStepFinished(pickle, 1, .{
        .status = .passed,
        .step_keyword = "When ",
        .step_text = "I add 3",
    });
    fmt.onTestStepFinished(pickle, 2, .{
        .status = .passed,
        .step_keyword = "Then ",
        .step_text = "I get 8",
    });

    fmt.onTestRunFinished(.{
        .total = 1,
        .passed = 1,
        .duration_ns = 1_500_000,
    });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Feature: features/math.feature") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Scenario: Adding numbers") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "✓ Given I have 5") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "✓ When I add 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "✓ Then I get 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1 scenario(s) (1 passed)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "0.001s") != null);
}

test "pretty formatter shows failed step with error" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var pretty = PrettyFormatter{
        .writer = writer,
        .use_colors = false,
    };

    const pickle = makeDummyPickle();
    pretty.onTestCaseStarted(.{ .pickle = pickle });
    pretty.onTestStepFinished(pickle, 0, .{
        .status = .failed,
        .step_keyword = "Then ",
        .step_text = "it fails",
        .err_message = "expected 5 but got 3",
    });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "✗ Then it fails") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "expected 5 but got 3") != null);
}

test "pretty formatter shows undefined step hint" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var pretty = PrettyFormatter{
        .writer = writer,
        .use_colors = false,
    };

    const pickle = makeDummyPickle();
    pretty.onTestCaseStarted(.{ .pickle = pickle });
    pretty.onTestStepFinished(pickle, 0, .{
        .status = .undefined,
        .step_keyword = "Given ",
        .step_text = "something unknown",
    });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "? Given something unknown") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "You can implement this step") != null);
}

test "pretty formatter prints tags" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var pretty = PrettyFormatter{
        .writer = writer,
        .use_colors = false,
    };

    const pickle = types.Pickle{
        .id = "1",
        .name = "Tagged scenario",
        .uri = "test.feature",
        .line = 1,
        .steps = &.{},
        .tags = &.{ .{ .name = "@smoke" }, .{ .name = "@fast" } },
    };

    pretty.onTestCaseStarted(.{ .pickle = pickle });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "@smoke") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "@fast") != null);
}

fn makeDummyPickle() types.Pickle {
    return .{
        .id = "1",
        .name = "dummy",
        .uri = "test.feature",
        .line = 1,
        .steps = &.{},
        .tags = &.{},
    };
}
