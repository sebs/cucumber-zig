const std = @import("std");
const testing = std.testing;
const Formatter = @import("Formatter.zig");
const types = @import("types.zig");

test "Formatter.init wires vtable from implementation" {
    const TestImpl = struct {
        run_started: bool = false,
        run_finished: bool = false,
        last_summary: ?types.RunSummary = null,

        pub fn onTestRunStarted(self: *@This()) void {
            self.run_started = true;
        }

        pub fn onTestRunFinished(self: *@This(), summary: types.RunSummary) void {
            self.run_finished = true;
            self.last_summary = summary;
        }
    };

    var impl = TestImpl{};
    const fmt = Formatter.init(&impl);

    // Should not crash — no-op for unimplemented callbacks
    fmt.onTestCaseStarted(.{ .pickle = makeDummyPickle() });
    fmt.onTestStepStarted(makeDummyPickle(), 0);
    fmt.onTestStepFinished(makeDummyPickle(), 0, .{ .status = .passed });
    fmt.onTestCaseFinished(.{
        .pickle = makeDummyPickle(),
        .step_results = &.{},
        .status = .passed,
        .duration_ns = 0,
    });

    // Should invoke real callbacks
    fmt.onTestRunStarted();
    try std.testing.expect(impl.run_started);

    const summary = types.RunSummary{ .total = 3, .passed = 2, .failed = 1, .duration_ns = 1_000_000 };
    fmt.onTestRunFinished(summary);
    try std.testing.expect(impl.run_finished);
    try std.testing.expectEqual(@as(u32, 3), impl.last_summary.?.total);
    try std.testing.expectEqual(@as(u32, 2), impl.last_summary.?.passed);
    try std.testing.expectEqual(@as(u32, 1), impl.last_summary.?.failed);
}

test "Formatter with no callbacks is safe" {
    const Empty = struct {};
    var empty = Empty{};
    const fmt = Formatter.init(&empty);

    // All calls should be no-ops
    fmt.onTestRunStarted();
    fmt.onTestCaseStarted(.{ .pickle = makeDummyPickle() });
    fmt.onTestStepStarted(makeDummyPickle(), 0);
    fmt.onTestStepFinished(makeDummyPickle(), 0, .{ .status = .passed });
    fmt.onTestCaseFinished(.{
        .pickle = makeDummyPickle(),
        .step_results = &.{},
        .status = .passed,
        .duration_ns = 0,
    });
    fmt.onTestRunFinished(.{});
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
