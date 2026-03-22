const std = @import("std");
const testing = std.testing;
const Runner = @import("runner.zig").Runner;
const StepRegistry = @import("step_registry.zig").StepRegistry;
const HookRegistry = @import("hooks.zig").HookRegistry;
const Fmt = @import("Formatter.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;

// A minimal StepRegistry mock for tests, since the real one may not exist yet.
// We re-use the same shape expected by the Runner.
const MockStepDef = struct {
    func: *const fn (world: *anyopaque, args: types.StepArgs) anyerror!void,
};

const MockMatchedStep = struct {
    step_def: *const MockStepDef,
    args: []const types.StepArg,
};

// Minimal World for testing.
const TestWorld = struct {
    value: i32 = 0,

    pub fn init(_: Allocator) !TestWorld {
        return .{ .value = 0 };
    }

    pub fn deinit(_: *TestWorld) void {}
};

// Tracking formatter for test assertions.
const TrackingFormatter = struct {
    run_started: bool = false,
    run_finished: bool = false,
    cases_started: u32 = 0,
    cases_finished: u32 = 0,
    steps_started: u32 = 0,
    steps_finished: u32 = 0,
    last_summary: ?types.RunSummary = null,
    last_case_result: ?types.TestCaseResult = null,

    pub fn onTestRunStarted(self: *TrackingFormatter) void {
        self.run_started = true;
    }

    pub fn onTestRunFinished(self: *TrackingFormatter, summary: types.RunSummary) void {
        self.run_finished = true;
        self.last_summary = summary;
    }

    pub fn onTestCaseStarted(self: *TrackingFormatter, _: types.TestCaseInfo) void {
        self.cases_started += 1;
    }

    pub fn onTestCaseFinished(self: *TrackingFormatter, result: types.TestCaseResult) void {
        self.cases_finished += 1;
        self.last_case_result = result;
    }

    pub fn onTestStepStarted(self: *TrackingFormatter, _: types.Pickle, _: usize) void {
        self.steps_started += 1;
    }

    pub fn onTestStepFinished(self: *TrackingFormatter, _: types.Pickle, _: usize, _: types.StepResult) void {
        self.steps_finished += 1;
    }
};

// Step functions for testing.
fn passingStep(_: *anyopaque, _: types.StepArgs) anyerror!void {}

fn failingStep(_: *anyopaque, _: types.StepArgs) anyerror!void {
    return error.AssertionFailed;
}

fn pendingStep(_: *anyopaque, _: types.StepArgs) anyerror!void {
    return error.Pending;
}

// Helper to build a simple pickle for tests.
fn makePickle(name: []const u8, steps: []const types.PickleStep, tags: []const types.PickleTag) types.Pickle {
    return .{
        .id = "test-pickle",
        .name = name,
        .uri = "test.feature",
        .line = 1,
        .steps = steps,
        .tags = tags,
    };
}

test "runner: simple passing scenario" {
    const alloc = testing.allocator;

    // Set up registries.
    var hook_registry = HookRegistry.init(alloc);
    defer hook_registry.deinit();

    var step_registry = StepRegistry.init(alloc);
    defer step_registry.deinit();

    // Register a step that matches "I do something".
    try step_registry.given("I do something", &passingStep);

    // Build runner.
    const R = Runner(TestWorld);
    var runner = R.init(alloc, &step_registry, &hook_registry);
    defer runner.deinit();

    var tracker = TrackingFormatter{};
    try runner.addFormatter(Fmt.init(&tracker));

    // Build pickle.
    const steps = [_]types.PickleStep{
        .{ .text = "I do something", .keyword = "Given" },
    };
    const pickles = [_]types.Pickle{
        makePickle("passing scenario", &steps, &.{}),
    };

    const summary = try runner.run(&pickles);

    try testing.expectEqual(@as(u32, 1), summary.total);
    try testing.expectEqual(@as(u32, 1), summary.passed);
    try testing.expectEqual(@as(u32, 0), summary.failed);
    try testing.expect(tracker.run_started);
    try testing.expect(tracker.run_finished);
    try testing.expectEqual(@as(u32, 1), tracker.cases_started);
    try testing.expectEqual(@as(u32, 1), tracker.cases_finished);
}

test "runner: undefined step" {
    const alloc = testing.allocator;

    var hook_registry = HookRegistry.init(alloc);
    defer hook_registry.deinit();

    var step_registry = StepRegistry.init(alloc);
    defer step_registry.deinit();

    // No steps registered — everything will be undefined.

    const R = Runner(TestWorld);
    var runner = R.init(alloc, &step_registry, &hook_registry);
    defer runner.deinit();

    var tracker = TrackingFormatter{};
    try runner.addFormatter(Fmt.init(&tracker));

    const steps = [_]types.PickleStep{
        .{ .text = "something undefined", .keyword = "When" },
        .{ .text = "another step", .keyword = "Then" },
    };
    const pickles = [_]types.Pickle{
        makePickle("undefined scenario", &steps, &.{}),
    };

    const summary = try runner.run(&pickles);

    try testing.expectEqual(@as(u32, 1), summary.total);
    try testing.expectEqual(@as(u32, 1), summary.undefined);
    try testing.expectEqual(@as(u32, 0), summary.passed);

    // The first step is undefined, the second should be skipped.
    if (tracker.last_case_result) |result| {
        try testing.expectEqual(@as(usize, 2), result.step_results.len);
        try testing.expectEqual(types.StepStatus.undefined, result.step_results[0].status);
        try testing.expectEqual(types.StepStatus.skipped, result.step_results[1].status);
    } else {
        return error.TestExpectedResult;
    }
}

test "runner: failing step" {
    const alloc = testing.allocator;

    var hook_registry = HookRegistry.init(alloc);
    defer hook_registry.deinit();

    var step_registry = StepRegistry.init(alloc);
    defer step_registry.deinit();

    try step_registry.given("this fails", &failingStep);
    try step_registry.given("this passes", &passingStep);

    const R = Runner(TestWorld);
    var runner = R.init(alloc, &step_registry, &hook_registry);
    defer runner.deinit();

    var tracker = TrackingFormatter{};
    try runner.addFormatter(Fmt.init(&tracker));

    const steps = [_]types.PickleStep{
        .{ .text = "this fails", .keyword = "Given" },
        .{ .text = "this passes", .keyword = "Then" },
    };
    const pickles = [_]types.Pickle{
        makePickle("failing scenario", &steps, &.{}),
    };

    const summary = try runner.run(&pickles);

    try testing.expectEqual(@as(u32, 1), summary.total);
    try testing.expectEqual(@as(u32, 1), summary.failed);
    try testing.expectEqual(@as(u32, 0), summary.passed);

    if (tracker.last_case_result) |result| {
        try testing.expectEqual(@as(usize, 2), result.step_results.len);
        try testing.expectEqual(types.StepStatus.failed, result.step_results[0].status);
        // Second step should be skipped because the first failed.
        try testing.expectEqual(types.StepStatus.skipped, result.step_results[1].status);
    } else {
        return error.TestExpectedResult;
    }
}

test "runner: tag filtering skips scenarios" {
    const alloc = testing.allocator;

    var hook_registry = HookRegistry.init(alloc);
    defer hook_registry.deinit();

    var step_registry = StepRegistry.init(alloc);
    defer step_registry.deinit();

    try step_registry.given("I do something", &passingStep);

    const R = Runner(TestWorld);
    var runner = R.init(alloc, &step_registry, &hook_registry);
    defer runner.deinit();

    // Only run scenarios tagged @smoke.
    try runner.setTagFilter("@smoke");

    var tracker = TrackingFormatter{};
    try runner.addFormatter(Fmt.init(&tracker));

    const steps = [_]types.PickleStep{
        .{ .text = "I do something", .keyword = "Given" },
    };

    const smoke_tag = [_]types.PickleTag{.{ .name = "@smoke" }};
    const wip_tag = [_]types.PickleTag{.{ .name = "@wip" }};

    const pickles = [_]types.Pickle{
        makePickle("smoke scenario", &steps, &smoke_tag),
        makePickle("wip scenario", &steps, &wip_tag),
    };

    const summary = try runner.run(&pickles);

    try testing.expectEqual(@as(u32, 2), summary.total);
    try testing.expectEqual(@as(u32, 1), summary.passed);
    try testing.expectEqual(@as(u32, 1), summary.skipped);
    try testing.expectEqual(@as(u32, 0), summary.failed);
}

test "runner: pending step status" {
    const alloc = testing.allocator;

    var hook_registry = HookRegistry.init(alloc);
    defer hook_registry.deinit();

    var step_registry = StepRegistry.init(alloc);
    defer step_registry.deinit();

    try step_registry.given("this is pending", &pendingStep);
    try step_registry.given("this passes", &passingStep);

    const R = Runner(TestWorld);
    var runner = R.init(alloc, &step_registry, &hook_registry);
    defer runner.deinit();

    var tracker = TrackingFormatter{};
    try runner.addFormatter(Fmt.init(&tracker));

    const steps = [_]types.PickleStep{
        .{ .text = "this is pending", .keyword = "Given" },
        .{ .text = "this passes", .keyword = "Then" },
    };
    const pickles = [_]types.Pickle{
        makePickle("pending scenario", &steps, &.{}),
    };

    const summary = try runner.run(&pickles);

    try testing.expectEqual(@as(u32, 1), summary.total);
    try testing.expectEqual(@as(u32, 1), summary.pending);
    try testing.expectEqual(@as(u32, 0), summary.passed);
    try testing.expectEqual(@as(u32, 0), summary.failed);

    if (tracker.last_case_result) |result| {
        try testing.expectEqual(@as(usize, 2), result.step_results.len);
        try testing.expectEqual(types.StepStatus.pending, result.step_results[0].status);
        // Second step should be skipped because the first is pending.
        try testing.expectEqual(types.StepStatus.skipped, result.step_results[1].status);
    } else {
        return error.TestExpectedResult;
    }
}

// Hook function that always fails.
fn failingBeforeHook(_: *anyopaque, _: types.ScenarioInfo) anyerror!void {
    return error.HookFailed;
}

test "runner: before hook failure skips steps and fails scenario" {
    const alloc = testing.allocator;

    var hook_registry = HookRegistry.init(alloc);
    defer hook_registry.deinit();

    var step_registry = StepRegistry.init(alloc);
    defer step_registry.deinit();

    // Register a Before hook that fails.
    try hook_registry.addBefore("failing setup", null, 0, &failingBeforeHook);

    try step_registry.given("I do something", &passingStep);

    const R = Runner(TestWorld);
    var runner = R.init(alloc, &step_registry, &hook_registry);
    defer runner.deinit();

    var tracker = TrackingFormatter{};
    try runner.addFormatter(Fmt.init(&tracker));

    const steps = [_]types.PickleStep{
        .{ .text = "I do something", .keyword = "Given" },
    };
    const pickles = [_]types.Pickle{
        makePickle("hook failure scenario", &steps, &.{}),
    };

    const summary = try runner.run(&pickles);

    try testing.expectEqual(@as(u32, 1), summary.total);
    try testing.expectEqual(@as(u32, 1), summary.failed);
    try testing.expectEqual(@as(u32, 0), summary.passed);

    if (tracker.last_case_result) |result| {
        // The scenario itself is failed.
        try testing.expectEqual(types.StepStatus.failed, result.status);
        // The step should be skipped because the Before hook failed.
        try testing.expectEqual(@as(usize, 1), result.step_results.len);
        try testing.expectEqual(types.StepStatus.skipped, result.step_results[0].status);
    } else {
        return error.TestExpectedResult;
    }
}

// Step function that validates it received a DataTable argument.
fn tableValidatingStep(_: *anyopaque, args: types.StepArgs) anyerror!void {
    // Find a table arg among the step arguments.
    for (args) |arg| {
        switch (arg) {
            .table => |dt| {
                // Validate the table has expected content.
                if (dt.rowCount() != 2) return error.UnexpectedRowCount;
                if (dt.colCount() != 2) return error.UnexpectedColCount;
                const header = dt.headerRow();
                if (!std.mem.eql(u8, header[0], "name")) return error.UnexpectedHeader;
                if (!std.mem.eql(u8, header[1], "value")) return error.UnexpectedHeader;
                const cell = dt.cell(1, 0) orelse return error.MissingCell;
                if (!std.mem.eql(u8, cell, "foo")) return error.UnexpectedCellValue;
                return;
            },
            else => {},
        }
    }
    return error.NoTableArgument;
}

test "runner: DataTable argument flows through runner" {
    const alloc = testing.allocator;

    var hook_registry = HookRegistry.init(alloc);
    defer hook_registry.deinit();

    var step_registry = StepRegistry.init(alloc);
    defer step_registry.deinit();

    try step_registry.given("a table step", &tableValidatingStep);

    const R = Runner(TestWorld);
    var runner = R.init(alloc, &step_registry, &hook_registry);
    defer runner.deinit();

    var tracker = TrackingFormatter{};
    try runner.addFormatter(Fmt.init(&tracker));

    // Build a pickle with a DataTable argument.
    const cells_row0 = [_]types.PickleTableCell{
        .{ .value = "name" },
        .{ .value = "value" },
    };
    const cells_row1 = [_]types.PickleTableCell{
        .{ .value = "foo" },
        .{ .value = "42" },
    };
    const table_rows = [_]types.PickleTableRow{
        .{ .cells = &cells_row0 },
        .{ .cells = &cells_row1 },
    };

    const steps = [_]types.PickleStep{
        .{
            .text = "a table step",
            .keyword = "Given",
            .argument = .{ .table = .{ .rows = &table_rows } },
        },
    };
    const pickles = [_]types.Pickle{
        makePickle("table scenario", &steps, &.{}),
    };

    const summary = try runner.run(&pickles);

    try testing.expectEqual(@as(u32, 1), summary.total);
    try testing.expectEqual(@as(u32, 1), summary.passed);
    try testing.expectEqual(@as(u32, 0), summary.failed);

    if (tracker.last_case_result) |result| {
        try testing.expectEqual(types.StepStatus.passed, result.status);
        try testing.expectEqual(@as(usize, 1), result.step_results.len);
        try testing.expectEqual(types.StepStatus.passed, result.step_results[0].status);
    } else {
        return error.TestExpectedResult;
    }
}

// Step function that validates it received a DocString argument.
fn docStringValidatingStep(_: *anyopaque, args: types.StepArgs) anyerror!void {
    for (args) |arg| {
        switch (arg) {
            .doc_string => |ds| {
                if (!std.mem.eql(u8, ds.content, "hello world")) return error.UnexpectedContent;
                const ct = ds.content_type orelse return error.MissingContentType;
                if (!std.mem.eql(u8, ct, "text/plain")) return error.UnexpectedContentType;
                return;
            },
            else => {},
        }
    }
    return error.NoDocStringArgument;
}

test "runner: DocString argument flows through runner" {
    const alloc = testing.allocator;

    var hook_registry = HookRegistry.init(alloc);
    defer hook_registry.deinit();

    var step_registry = StepRegistry.init(alloc);
    defer step_registry.deinit();

    try step_registry.given("a doc string step", &docStringValidatingStep);

    const R = Runner(TestWorld);
    var runner = R.init(alloc, &step_registry, &hook_registry);
    defer runner.deinit();

    var tracker = TrackingFormatter{};
    try runner.addFormatter(Fmt.init(&tracker));

    // Build a pickle with a DocString argument.
    const steps = [_]types.PickleStep{
        .{
            .text = "a doc string step",
            .keyword = "Given",
            .argument = .{ .doc_string = .{
                .content = "hello world",
                .media_type = "text/plain",
            } },
        },
    };
    const pickles = [_]types.Pickle{
        makePickle("doc string scenario", &steps, &.{}),
    };

    const summary = try runner.run(&pickles);

    try testing.expectEqual(@as(u32, 1), summary.total);
    try testing.expectEqual(@as(u32, 1), summary.passed);
    try testing.expectEqual(@as(u32, 0), summary.failed);

    if (tracker.last_case_result) |result| {
        try testing.expectEqual(types.StepStatus.passed, result.status);
        try testing.expectEqual(@as(usize, 1), result.step_results.len);
        try testing.expectEqual(types.StepStatus.passed, result.step_results[0].status);
    } else {
        return error.TestExpectedResult;
    }
}
