const std = @import("std");
const testing = std.testing;
const HookRegistry = @import("hooks.zig").HookRegistry;
const types = @import("types.zig");

// ── Test helpers ──

fn dummyHook(_: *anyopaque, _: types.ScenarioInfo) anyerror!void {}
fn dummySuiteHook() anyerror!void {}

test "add and retrieve before hooks" {
    const allocator = testing.allocator;
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    try registry.addBefore("setup world", null, 0, &dummyHook);
    try registry.addBefore("setup db", null, 0, &dummyHook);

    const hooks = registry.getBeforeHooks(&.{});
    try testing.expectEqual(@as(usize, 2), hooks.len);
    try testing.expectEqualStrings("setup world", hooks[0].name);
    try testing.expectEqualStrings("setup db", hooks[1].name);
}

test "add and retrieve after hooks" {
    const allocator = testing.allocator;
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    try registry.addAfter("cleanup", null, 0, &dummyHook);

    const hooks = registry.getAfterHooks(&.{});
    try testing.expectEqual(@as(usize, 1), hooks.len);
    try testing.expectEqualStrings("cleanup", hooks[0].name);
}

test "add and retrieve suite hooks" {
    const allocator = testing.allocator;
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    try registry.addBeforeAll("global setup", 0, &dummySuiteHook);
    try registry.addAfterAll("global teardown", 0, &dummySuiteHook);

    const before_all = registry.getBeforeAllHooks();
    try testing.expectEqual(@as(usize, 1), before_all.len);
    try testing.expectEqualStrings("global setup", before_all[0].name);

    const after_all = registry.getAfterAllHooks();
    try testing.expectEqual(@as(usize, 1), after_all.len);
    try testing.expectEqualStrings("global teardown", after_all[0].name);
}

test "before hooks execute in ascending order" {
    const allocator = testing.allocator;
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    try registry.addBefore("third", null, 30, &dummyHook);
    try registry.addBefore("first", null, 10, &dummyHook);
    try registry.addBefore("second", null, 20, &dummyHook);

    const hooks = registry.getBeforeHooks(&.{});
    try testing.expectEqual(@as(usize, 3), hooks.len);
    try testing.expectEqualStrings("first", hooks[0].name);
    try testing.expectEqualStrings("second", hooks[1].name);
    try testing.expectEqualStrings("third", hooks[2].name);
}

test "after hooks execute in descending order" {
    const allocator = testing.allocator;
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    try registry.addAfter("third", null, 30, &dummyHook);
    try registry.addAfter("first", null, 10, &dummyHook);
    try registry.addAfter("second", null, 20, &dummyHook);

    const hooks = registry.getAfterHooks(&.{});
    try testing.expectEqual(@as(usize, 3), hooks.len);
    try testing.expectEqualStrings("third", hooks[0].name);
    try testing.expectEqualStrings("second", hooks[1].name);
    try testing.expectEqualStrings("first", hooks[2].name);
}

test "before step hooks ascending, after step hooks descending" {
    const allocator = testing.allocator;
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    try registry.addBeforeStep("b", null, 20, &dummyHook);
    try registry.addBeforeStep("a", null, 10, &dummyHook);
    try registry.addAfterStep("y", null, 20, &dummyHook);
    try registry.addAfterStep("z", null, 30, &dummyHook);

    const bs = registry.getBeforeStepHooks(&.{});
    try testing.expectEqual(@as(usize, 2), bs.len);
    try testing.expectEqualStrings("a", bs[0].name);
    try testing.expectEqualStrings("b", bs[1].name);

    const as_ = registry.getAfterStepHooks(&.{});
    try testing.expectEqual(@as(usize, 2), as_.len);
    try testing.expectEqualStrings("z", as_[0].name);
    try testing.expectEqualStrings("y", as_[1].name);
}

test "suite hooks ordering" {
    const allocator = testing.allocator;
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    try registry.addBeforeAll("second", 20, &dummySuiteHook);
    try registry.addBeforeAll("first", 10, &dummySuiteHook);
    try registry.addAfterAll("early", 10, &dummySuiteHook);
    try registry.addAfterAll("late", 20, &dummySuiteHook);

    const ba = registry.getBeforeAllHooks();
    try testing.expectEqual(@as(usize, 2), ba.len);
    try testing.expectEqualStrings("first", ba[0].name);
    try testing.expectEqualStrings("second", ba[1].name);

    const aa = registry.getAfterAllHooks();
    try testing.expectEqual(@as(usize, 2), aa.len);
    try testing.expectEqualStrings("late", aa[0].name);
    try testing.expectEqualStrings("early", aa[1].name);
}

test "tag filtering: hooks without filter match everything" {
    const allocator = testing.allocator;
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    try registry.addBefore("always", null, 0, &dummyHook);

    const hooks = registry.getBeforeHooks(&.{"@smoke"});
    try testing.expectEqual(@as(usize, 1), hooks.len);
    try testing.expectEqualStrings("always", hooks[0].name);

    const hooks_empty = registry.getBeforeHooks(&.{});
    try testing.expectEqual(@as(usize, 1), hooks_empty.len);
}

test "tag filtering: hooks with filter only match relevant tags" {
    const allocator = testing.allocator;
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    try registry.addBefore("smoke only", "@smoke", 10, &dummyHook);
    try registry.addBefore("always", null, 20, &dummyHook);

    // Scenario with @smoke tag: both hooks match
    const hooks_smoke = registry.getBeforeHooks(&.{"@smoke"});
    try testing.expectEqual(@as(usize, 2), hooks_smoke.len);

    // Scenario without @smoke tag: only the unfiltered hook matches
    const hooks_none = registry.getBeforeHooks(&.{"@regression"});
    try testing.expectEqual(@as(usize, 1), hooks_none.len);
    try testing.expectEqualStrings("always", hooks_none[0].name);

    // Scenario with no tags at all: only the unfiltered hook matches
    const hooks_empty = registry.getBeforeHooks(&.{});
    try testing.expectEqual(@as(usize, 1), hooks_empty.len);
    try testing.expectEqualStrings("always", hooks_empty[0].name);
}

test "tag filtering on after hooks with ordering" {
    const allocator = testing.allocator;
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    try registry.addAfter("cleanup db", "@db", 10, &dummyHook);
    try registry.addAfter("screenshot", null, 20, &dummyHook);
    try registry.addAfter("log", null, 30, &dummyHook);

    // Scenario with @db: all three hooks, in descending order
    const hooks_db = registry.getAfterHooks(&.{"@db"});
    try testing.expectEqual(@as(usize, 3), hooks_db.len);
    try testing.expectEqualStrings("log", hooks_db[0].name);
    try testing.expectEqualStrings("screenshot", hooks_db[1].name);
    try testing.expectEqualStrings("cleanup db", hooks_db[2].name);

    // Scenario without @db: only the unfiltered hooks
    const hooks_no_db = registry.getAfterHooks(&.{});
    try testing.expectEqual(@as(usize, 2), hooks_no_db.len);
    try testing.expectEqualStrings("log", hooks_no_db[0].name);
    try testing.expectEqualStrings("screenshot", hooks_no_db[1].name);
}

test "empty registry returns empty slices" {
    const allocator = testing.allocator;
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    try testing.expectEqual(@as(usize, 0), registry.getBeforeHooks(&.{}).len);
    try testing.expectEqual(@as(usize, 0), registry.getAfterHooks(&.{}).len);
    try testing.expectEqual(@as(usize, 0), registry.getBeforeStepHooks(&.{}).len);
    try testing.expectEqual(@as(usize, 0), registry.getAfterStepHooks(&.{}).len);
    try testing.expectEqual(@as(usize, 0), registry.getBeforeAllHooks().len);
    try testing.expectEqual(@as(usize, 0), registry.getAfterAllHooks().len);
}
