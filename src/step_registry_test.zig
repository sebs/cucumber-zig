const std = @import("std");
const testing = std.testing;
const StepRegistry = @import("step_registry.zig").StepRegistry;
const types = @import("types.zig");
const Expression = @import("expression.zig");

// Check if we can actually compile expressions (requires regex module).
const has_regex = @hasDecl(Expression, "compile");

fn dummyStep(_: *anyopaque, _: types.StepArgs) anyerror!void {}
fn anotherStep(_: *anyopaque, _: types.StepArgs) anyerror!void {}

test "register and find a step" {
    if (!has_regex) return error.SkipZigTest;
    var registry = StepRegistry.init(testing.allocator);
    defer registry.deinit();

    try registry.given("I have {int} cucumbers", dummyStep);
    try testing.expectEqual(@as(usize, 1), registry.count());

    if (try registry.findMatch("I have 42 cucumbers", testing.allocator)) |*matched_| {
        var matched = matched_;
        defer matched.match_result.deinit();
        try testing.expectEqual(@as(usize, 1), matched.args.len);
        try testing.expectEqual(@as(i64, 42), matched.args[0].int);
        try testing.expectEqual(types.Keyword.given, matched.step_def.keyword);
    } else {
        return error.TestExpectedMatch;
    }
}

test "no match returns null" {
    if (!has_regex) return error.SkipZigTest;
    var registry = StepRegistry.init(testing.allocator);
    defer registry.deinit();

    try registry.given("I have {int} cucumbers", dummyStep);

    const result = try registry.findMatch("something else entirely", testing.allocator);
    try testing.expect(result == null);
}

test "ambiguous steps return error" {
    if (!has_regex) return error.SkipZigTest;
    var registry = StepRegistry.init(testing.allocator);
    defer registry.deinit();

    // Two patterns that both match the same text.
    try registry.given("I have {} cucumbers", dummyStep);
    try registry.given("I have {int} cucumbers", anotherStep);

    const result = registry.findMatch("I have 42 cucumbers", testing.allocator);
    try testing.expectError(error.AmbiguousStep, result);
}

test "multiple registrations with different keywords" {
    if (!has_regex) return error.SkipZigTest;
    var registry = StepRegistry.init(testing.allocator);
    defer registry.deinit();

    try registry.given("a user {word}", dummyStep);
    try registry.when("the user logs in", dummyStep);
    try registry.then("the user sees {string}", dummyStep);
    try testing.expectEqual(@as(usize, 3), registry.count());

    // Match the Given step.
    if (try registry.findMatch("a user alice", testing.allocator)) |*matched_| {
        var matched = matched_;
        defer matched.match_result.deinit();
        try testing.expect(std.mem.eql(u8, "alice", matched.args[0].string));
        try testing.expectEqual(types.Keyword.given, matched.step_def.keyword);
    } else {
        return error.TestExpectedMatch;
    }

    // Match the When step.
    if (try registry.findMatch("the user logs in", testing.allocator)) |*matched_| {
        var matched = matched_;
        defer matched.match_result.deinit();
        try testing.expectEqual(@as(usize, 0), matched.args.len);
        try testing.expectEqual(types.Keyword.when, matched.step_def.keyword);
    } else {
        return error.TestExpectedMatch;
    }

    // Match the Then step.
    if (try registry.findMatch("the user sees \"dashboard\"", testing.allocator)) |*matched_| {
        var matched = matched_;
        defer matched.match_result.deinit();
        try testing.expect(std.mem.eql(u8, "dashboard", matched.args[0].string));
        try testing.expectEqual(types.Keyword.then, matched.step_def.keyword);
    } else {
        return error.TestExpectedMatch;
    }
}

test "keyword is for diagnostics only - matching ignores keywords" {
    if (!has_regex) return error.SkipZigTest;
    var registry = StepRegistry.init(testing.allocator);
    defer registry.deinit();

    // Register as "given" but match text that would semantically be a "then".
    try registry.given("the result is {int}", dummyStep);

    if (try registry.findMatch("the result is 100", testing.allocator)) |*matched_| {
        var matched = matched_;
        defer matched.match_result.deinit();
        try testing.expectEqual(@as(i64, 100), matched.args[0].int);
    } else {
        return error.TestExpectedMatch;
    }
}

test "step with raw regex pattern" {
    if (!has_regex) return error.SkipZigTest;
    var registry = StepRegistry.init(testing.allocator);
    defer registry.deinit();

    try registry.step(.any, "^I have (\\d+) items$", dummyStep);

    if (try registry.findMatch("I have 7 items", testing.allocator)) |*matched_| {
        var matched = matched_;
        defer matched.match_result.deinit();
        try testing.expectEqual(@as(usize, 1), matched.args.len);
        try testing.expect(std.mem.eql(u8, "7", matched.args[0].string));
    } else {
        return error.TestExpectedMatch;
    }
}

test "checkAmbiguities detects overlapping patterns" {
    if (!has_regex) return error.SkipZigTest;
    var registry = StepRegistry.init(testing.allocator);
    defer registry.deinit();

    // The literal pattern text "3 items" matches the regex produced by
    // "{int} items" (which is ^(-?\d+) items$), so checkAmbiguities
    // should detect the overlap.
    try registry.given("{int} items", dummyStep);
    try registry.when("3 items", anotherStep);

    const result = registry.checkAmbiguities();
    try testing.expectError(error.AmbiguousStep, result);
}

test "checkAmbiguities passes for non-overlapping patterns" {
    if (!has_regex) return error.SkipZigTest;
    var registry = StepRegistry.init(testing.allocator);
    defer registry.deinit();

    try registry.given("I have {int} cucumbers", dummyStep);
    try registry.when("the user logs in", anotherStep);

    // Should not return an error since the patterns do not overlap.
    try registry.checkAmbiguities();
}
