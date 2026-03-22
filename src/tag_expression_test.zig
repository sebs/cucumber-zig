const std = @import("std");
const testing = std.testing;
const TagExpression = @import("tag_expression.zig").TagExpression;

test "single tag matches" {
    var expr = try TagExpression.parse("@smoke", testing.allocator);
    defer expr.deinit();

    try testing.expect(expr.evaluate(&.{"@smoke"}));
    try testing.expect(!expr.evaluate(&.{"@wip"}));
}

test "and expression" {
    var expr = try TagExpression.parse("@smoke and @fast", testing.allocator);
    defer expr.deinit();

    try testing.expect(expr.evaluate(&.{ "@smoke", "@fast" }));
    try testing.expect(!expr.evaluate(&.{"@smoke"}));
    try testing.expect(!expr.evaluate(&.{"@fast"}));
}

test "or expression" {
    var expr = try TagExpression.parse("@smoke or @wip", testing.allocator);
    defer expr.deinit();

    try testing.expect(expr.evaluate(&.{"@smoke"}));
    try testing.expect(expr.evaluate(&.{"@wip"}));
    try testing.expect(!expr.evaluate(&.{"@other"}));
}

test "not expression" {
    var expr = try TagExpression.parse("not @slow", testing.allocator);
    defer expr.deinit();

    try testing.expect(expr.evaluate(&.{"@fast"}));
    try testing.expect(!expr.evaluate(&.{"@slow"}));
}

test "complex expression with parens and precedence" {
    var expr = try TagExpression.parse("(@smoke or @wip) and not @slow", testing.allocator);
    defer expr.deinit();

    // @smoke, not @slow -> true
    try testing.expect(expr.evaluate(&.{"@smoke"}));
    // @wip, not @slow -> true
    try testing.expect(expr.evaluate(&.{"@wip"}));
    // @smoke but also @slow -> false
    try testing.expect(!expr.evaluate(&.{ "@smoke", "@slow" }));
    // @wip but also @slow -> false
    try testing.expect(!expr.evaluate(&.{ "@wip", "@slow" }));
    // neither @smoke nor @wip -> false
    try testing.expect(!expr.evaluate(&.{"@other"}));
}

test "empty expression matches everything" {
    var expr = try TagExpression.parse("", testing.allocator);
    defer expr.deinit();

    try testing.expect(expr.evaluate(&.{"@anything"}));
    try testing.expect(expr.evaluate(&.{}));
}

test "precedence: not binds tighter than and" {
    // "not @a and @b" should parse as "(not @a) and @b"
    var expr = try TagExpression.parse("not @a and @b", testing.allocator);
    defer expr.deinit();

    try testing.expect(expr.evaluate(&.{"@b"}));
    try testing.expect(!expr.evaluate(&.{ "@a", "@b" }));
    try testing.expect(!expr.evaluate(&.{"@a"}));
}

test "precedence: and binds tighter than or" {
    // "@a or @b and @c" should parse as "@a or (@b and @c)"
    var expr = try TagExpression.parse("@a or @b and @c", testing.allocator);
    defer expr.deinit();

    try testing.expect(expr.evaluate(&.{"@a"}));
    try testing.expect(expr.evaluate(&.{ "@b", "@c" }));
    try testing.expect(!expr.evaluate(&.{"@b"}));
}

test "double not" {
    var expr = try TagExpression.parse("not not @a", testing.allocator);
    defer expr.deinit();

    try testing.expect(expr.evaluate(&.{"@a"}));
    try testing.expect(!expr.evaluate(&.{"@b"}));
}

test "whitespace-only expression matches everything" {
    var expr = try TagExpression.parse("   ", testing.allocator);
    defer expr.deinit();

    try testing.expect(expr.evaluate(&.{}));
}
