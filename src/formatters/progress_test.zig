const std = @import("std");
const types = @import("../types.zig");
const ProgressFormatter = @import("progress.zig");

test "progress formatter prints dots for passed steps" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var progress = ProgressFormatter{
        .writer = writer,
        .use_colors = false,
    };
    var fmt = progress.formatter();

    const pickle = makeDummyPickle();

    fmt.onTestStepFinished(pickle, 0, .{ .status = .passed, .step_keyword = "Given ", .step_text = "a" });
    fmt.onTestStepFinished(pickle, 1, .{ .status = .passed, .step_keyword = "When ", .step_text = "b" });
    fmt.onTestStepFinished(pickle, 2, .{ .status = .passed, .step_keyword = "Then ", .step_text = "c" });

    const output = fbs.getWritten();
    try std.testing.expectEqualStrings("...", output);
}

test "progress formatter prints mixed status characters" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var progress = ProgressFormatter{
        .writer = writer,
        .use_colors = false,
    };

    const pickle = makeDummyPickle();

    progress.onTestStepFinished(pickle, 0, .{ .status = .passed });
    progress.onTestStepFinished(pickle, 1, .{ .status = .failed });
    progress.onTestStepFinished(pickle, 2, .{ .status = .undefined });
    progress.onTestStepFinished(pickle, 3, .{ .status = .pending });
    progress.onTestStepFinished(pickle, 4, .{ .status = .skipped });

    const output = fbs.getWritten();
    try std.testing.expectEqualStrings(".FUP-", output);
}

test "progress formatter prints summary" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var progress = ProgressFormatter{
        .writer = writer,
        .use_colors = false,
    };

    progress.onTestRunFinished(.{
        .total = 5,
        .passed = 3,
        .failed = 1,
        .skipped = 1,
        .duration_ns = 2_345_000_000,
    });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "5 scenario(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "3 passed") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1 failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1 skipped") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "2.345s") != null);
}

test "progress formatter wraps at 70 characters" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer().any();

    var progress = ProgressFormatter{
        .writer = writer,
        .use_colors = false,
    };

    const pickle = makeDummyPickle();
    for (0..71) |i| {
        progress.onTestStepFinished(pickle, i, .{ .status = .passed });
    }

    const output = fbs.getWritten();
    // 70 dots + newline + 1 dot = 72 bytes
    try std.testing.expectEqual(@as(usize, 72), output.len);
    try std.testing.expectEqual(@as(u8, '\n'), output[70]);
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
