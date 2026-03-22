/// Conformance tests for the Cucumber Expression compiler, ported from the
/// official test suite at https://github.com/cucumber/cucumber-expressions
///
/// These tests validate our implementation against the canonical specification
/// defined in testdata/cucumber-expression/matching/*.yaml and
/// testdata/cucumber-expression/transformation/*.yaml.
const std = @import("std");
const testing = std.testing;
const Expression = @import("expression.zig");

// ── Helpers ──

fn expectMatch(expression: []const u8, text: []const u8, expected_args: []const []const u8) !void {
    var expr = Expression.compile(expression, testing.allocator) catch |err| {
        std.debug.print("Failed to compile expression '{s}': {}\n", .{ expression, err });
        return err;
    };
    defer expr.deinit();

    const maybe_result = try expr.match(text);
    if (maybe_result) |result| {
        defer result.deinit();
        try testing.expectEqual(expected_args.len, result.args.len);
        for (expected_args, 0..) |expected, i| {
            const actual = switch (result.args[i]) {
                .string => |s| s,
                .int => |v| blk: {
                    var buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable;
                    break :blk s;
                },
                .float => |v| blk: {
                    var buf: [64]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable;
                    break :blk s;
                },
                else => "(other)",
            };
            if (!std.mem.eql(u8, expected, actual)) {
                std.debug.print("Arg {d}: expected '{s}', got '{s}'\n", .{ i, expected, actual });
                return error.TestExpectedEqual;
            }
        }
    } else {
        std.debug.print("Expression '{s}' failed to match '{s}'\n", .{ expression, text });
        return error.TestExpectedMatch;
    }
}

fn expectNoMatch(expression: []const u8, text: []const u8) !void {
    var expr = Expression.compile(expression, testing.allocator) catch |err| {
        std.debug.print("Failed to compile expression '{s}': {}\n", .{ expression, err });
        return err;
    };
    defer expr.deinit();

    const maybe_result = try expr.match(text);
    if (maybe_result) |result| {
        result.deinit();
        std.debug.print("Expression '{s}' unexpectedly matched '{s}'\n", .{ expression, text });
        return error.TestUnexpectedMatch;
    }
    // Expected: no match
}

fn expectMatchInt(expression: []const u8, text: []const u8, expected: i64) !void {
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{expected}) catch unreachable;
    try expectMatch(expression, text, &.{s});
}

// ── Official matching tests: integers ──
// Source: testdata/cucumber-expression/matching/matches-int.yaml

test "conformance: {int} matches positive integer" {
    try expectMatchInt("{int}", "2147483647", 2147483647);
}

test "conformance: {int} matches negative integer" {
    try expectMatchInt("{int}", "-2147483647", -2147483647);
}

test "conformance: {int} does not match float" {
    try expectNoMatch("{int}", "1.22");
}

// ── Official matching tests: floats ──
// Source: testdata/cucumber-expression/matching/matches-float*.yaml

test "conformance: {float} matches float" {
    try expectMatch("{float}", "3.141593", &.{"3.141593"});
}

test "conformance: {float} matches float with integer part" {
    try expectMatch("{float}", "0.22", &.{"0.22"});
}

test "conformance: {float} matches float without integer part" {
    // Official: expected_args: [0.22]. Our parser returns 0.22 as f64.
    try expectMatch("{float}", ".22", &.{"0.22"});
}

test "conformance: {float} matches negative float" {
    try expectMatch("{float}", "-3.141593", &.{"-3.141593"});
}

// ── Official matching tests: word ──
// Source: testdata/cucumber-expression/matching/matches-word.yaml

test "conformance: {word} matches word" {
    try expectMatch("three {word} mice", "three blind mice", &.{"blind"});
}

// ── Official matching tests: string ──
// Source: testdata/cucumber-expression/matching/matches-*-string*.yaml

test "conformance: {string} matches double-quoted string" {
    try expectMatch("three {string} mice", "three \"blind\" mice", &.{"blind"});
}

test "conformance: {string} matches single-quoted string" {
    try expectMatch("three {string} mice", "three 'blind' mice", &.{"blind"});
}

test "conformance: {string} matches double-quoted empty string" {
    try expectMatch("three {string} mice", "three \"\" mice", &.{""});
}

test "conformance: multiple {string} captures" {
    try expectMatch(
        "three {string} and {string} mice",
        "three \"blind\" and \"crippled\" mice",
        &.{ "blind", "crippled" },
    );
}

// ── Official matching tests: anonymous ──
// Source: testdata/cucumber-expression/matching/matches-anonymous-parameter-type.yaml

test "conformance: {} matches anonymous parameter" {
    try expectMatch("{}", "0.22", &.{"0.22"});
}

// ── Official matching tests: alternation ──
// Source: testdata/cucumber-expression/matching/matches-alternation.yaml

test "conformance: alternation with escaped slash" {
    // expression: mice/rats and rats\/mice
    // text: rats and rats/mice
    // The escaped slash \/ becomes a literal slash
    try expectMatch("mice/rats and rats\\/mice", "rats and rats/mice", &.{});
}

// ── Official matching tests: optional ──
// Source: testdata/cucumber-expression/matching/matches-optional-in-alternation-1.yaml

test "conformance: optional in alternation" {
    // {int} rat(s)/mouse/mice  matches "3 rats" → [3]
    try expectMatchInt("{int} rat(s)/mouse/mice", "3 rats", 3);
}

// ── Official matching tests: escaped characters ──
// Source: testdata/cucumber-expression/matching/matches-escaped-parenthesis-1.yaml

test "conformance: escaped parenthesis matches literal" {
    // \(exceptionally) \{string} mice
    // matches: (exceptionally) {string} mice
    // No captures (everything is escaped)
    try expectMatch(
        "\\(exceptionally) \\{string} mice",
        "(exceptionally) {string} mice",
        &.{},
    );
}

// Source: testdata/cucumber-expression/matching/matches-escaped-slash.yaml

test "conformance: escaped slash matches literal" {
    // 12\/2020 matches 12/2020
    try expectMatch("12\\/2020", "12/2020", &.{});
}

// ── Official transformation tests ──
// These test that expressions compile to the expected regex patterns.
// Our regex patterns may differ from the official spec but must produce
// equivalent matching behavior.

test "conformance: transformation - text" {
    // expression: a  →  expected_regex: ^a$
    var expr = try Expression.compile("a", testing.allocator);
    defer expr.deinit();
    try testing.expect(!expr.is_raw_regex);
    // Verify it matches the right text
    if (try expr.match("a")) |result| {
        defer result.deinit();
        try testing.expectEqual(@as(usize, 0), result.args.len);
    } else return error.TestExpectedMatch;
    // Should not match other text
    const no_match = try expr.match("b");
    try testing.expect(no_match == null);
}

test "conformance: transformation - empty" {
    // expression: ''  →  expected_regex: ^$
    var expr = try Expression.compile("", testing.allocator);
    defer expr.deinit();
    if (try expr.match("")) |result| {
        defer result.deinit();
        try testing.expectEqual(@as(usize, 0), result.args.len);
    } else return error.TestExpectedMatch;
}

test "conformance: transformation - optional" {
    // expression: (a)  →  expected_regex: ^(?:a)?$
    var expr = try Expression.compile("(a)", testing.allocator);
    defer expr.deinit();
    // Should match both "a" and ""
    {
        if (try expr.match("a")) |result| {
            result.deinit();
        } else return error.TestExpectedMatch;
    }
    {
        if (try expr.match("")) |result| {
            result.deinit();
        } else return error.TestExpectedMatch;
    }
}

test "conformance: transformation - alternation" {
    // expression: a/b c/d/e  →  expected_regex: ^(?:a|b) (?:c|d|e)$
    var expr = try Expression.compile("a/b c/d/e", testing.allocator);
    defer expr.deinit();
    // Should match "a c", "b d", "a e", etc.
    {
        if (try expr.match("a c")) |result| {
            result.deinit();
        } else return error.TestExpectedMatch;
    }
    {
        if (try expr.match("b e")) |result| {
            result.deinit();
        } else return error.TestExpectedMatch;
    }
    // Should not match "a b" (wrong combination for second group)
    {
        const r = try expr.match("a b");
        try testing.expect(r == null);
    }
}

test "conformance: transformation - parameter" {
    // expression: {int}  →  expected_regex: ^((?:-?\d+)|(?:\d+))$
    var expr = try Expression.compile("{int}", testing.allocator);
    defer expr.deinit();
    // Must match positive and negative integers
    {
        if (try expr.match("42")) |result| {
            defer result.deinit();
            try testing.expectEqual(@as(i64, 42), result.args[0].int);
        } else return error.TestExpectedMatch;
    }
    {
        if (try expr.match("-7")) |result| {
            defer result.deinit();
            try testing.expectEqual(@as(i64, -7), result.args[0].int);
        } else return error.TestExpectedMatch;
    }
}

test "conformance: transformation - alternation with optional" {
    // expression: a/b(c)  →  expected_regex: ^(?:a|b(?:c)?)$
    var expr = try Expression.compile("a/b(c)", testing.allocator);
    defer expr.deinit();
    // Should match "a", "b", "bc"
    for ([_][]const u8{ "a", "b", "bc" }) |text| {
        if (try expr.match(text)) |result| {
            result.deinit();
        } else {
            std.debug.print("Expected match for '{s}'\n", .{text});
            return error.TestExpectedMatch;
        }
    }
}
