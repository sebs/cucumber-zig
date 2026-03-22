const std = @import("std");
const testing = std.testing;
const Regex = @import("regex.zig").Regex;
const expression = @import("expression.zig");
const compile = expression.compile;
const CompiledExpression = expression.CompiledExpression;
const ParamType = expression.ParamType;
const isRawRegex = expression.isRawRegex;

// The tests below verify the compilation logic (regex pattern generation)
// and the auto-detection heuristic. Full match tests require a working
// Regex implementation; they are guarded by a comptime check.
const has_regex = blk: {
    // Try to detect if Regex is available for testing.
    // In unit test mode with the real regex module, this will be true.
    break :blk @hasDecl(Regex, "compile");
};

test "auto-detect: raw regex starting with ^" {
    try testing.expect(isRawRegex("^foo.*bar$"));
    try testing.expect(isRawRegex("^hello"));
}

test "auto-detect: raw regex ending with $" {
    try testing.expect(isRawRegex("foo$"));
}

test "auto-detect: cucumber expression" {
    try testing.expect(!isRawRegex("I have {int} cucumbers"));
    try testing.expect(!isRawRegex("hello world"));
    try testing.expect(!isRawRegex("{word} is logged in"));
}

test "compile cucumber expression - int parameter" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("I have {int} cucumbers", testing.allocator);
    defer expr.deinit();

    try testing.expect(!expr.is_raw_regex);
    try testing.expectEqual(@as(usize, 1), expr.captures.len);
    try testing.expectEqual(ParamType.int, expr.captures[0].param_type);
    try testing.expectEqual(@as(u32, 1), expr.captures[0].group_index);

    if (try expr.match("I have 42 cucumbers")) |result| {
        defer result.deinit();
        try testing.expectEqual(@as(usize, 1), result.args.len);
        try testing.expectEqual(@as(i64, 42), result.args[0].int);
    } else {
        return error.TestExpectedMatch;
    }
}

test "compile cucumber expression - negative int" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("balance is {int}", testing.allocator);
    defer expr.deinit();

    if (try expr.match("balance is -7")) |result| {
        defer result.deinit();
        try testing.expectEqual(@as(i64, -7), result.args[0].int);
    } else {
        return error.TestExpectedMatch;
    }
}

test "compile cucumber expression - float parameter" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("I have {float} kg", testing.allocator);
    defer expr.deinit();

    if (try expr.match("I have 3.14 kg")) |result| {
        defer result.deinit();
        try testing.expectEqual(@as(f64, 3.14), result.args[0].float);
    } else {
        return error.TestExpectedMatch;
    }
}

test "compile cucumber expression - word parameter" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("{word} is logged in", testing.allocator);
    defer expr.deinit();

    if (try expr.match("alice is logged in")) |result| {
        defer result.deinit();
        try testing.expect(std.mem.eql(u8, "alice", result.args[0].string));
    } else {
        return error.TestExpectedMatch;
    }
}

test "compile cucumber expression - string parameter (double quotes)" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("a {string} message", testing.allocator);
    defer expr.deinit();

    if (try expr.match("a \"hello\" message")) |result| {
        defer result.deinit();
        try testing.expect(std.mem.eql(u8, "hello", result.args[0].string));
    } else {
        return error.TestExpectedMatch;
    }
}

test "compile cucumber expression - string parameter (single quotes)" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("a {string} message", testing.allocator);
    defer expr.deinit();

    if (try expr.match("a 'world' message")) |result| {
        defer result.deinit();
        try testing.expect(std.mem.eql(u8, "world", result.args[0].string));
    } else {
        return error.TestExpectedMatch;
    }
}

test "compile cucumber expression - anonymous parameter" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("I see {}", testing.allocator);
    defer expr.deinit();

    if (try expr.match("I see anything at all")) |result| {
        defer result.deinit();
        try testing.expect(std.mem.eql(u8, "anything at all", result.args[0].string));
    } else {
        return error.TestExpectedMatch;
    }
}

test "compile cucumber expression - optional text" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("I have {int} cucumber(s)", testing.allocator);
    defer expr.deinit();

    // Plural form.
    if (try expr.match("I have 5 cucumbers")) |result| {
        defer result.deinit();
        try testing.expectEqual(@as(i64, 5), result.args[0].int);
    } else {
        return error.TestExpectedMatch;
    }

    // Singular form.
    if (try expr.match("I have 1 cucumber")) |result| {
        defer result.deinit();
        try testing.expectEqual(@as(i64, 1), result.args[0].int);
    } else {
        return error.TestExpectedMatch;
    }
}

test "compile cucumber expression - alternation" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("I am a/an admin", testing.allocator);
    defer expr.deinit();

    if (try expr.match("I am a admin")) |result| {
        defer result.deinit();
        try testing.expectEqual(@as(usize, 0), result.args.len);
    } else {
        return error.TestExpectedMatch;
    }

    if (try expr.match("I am an admin")) |result| {
        defer result.deinit();
        try testing.expectEqual(@as(usize, 0), result.args.len);
    } else {
        return error.TestExpectedMatch;
    }
}

test "compile cucumber expression - no match returns null" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("I have {int} cucumbers", testing.allocator);
    defer expr.deinit();

    const result = try expr.match("something completely different");
    try testing.expect(result == null);
}

test "compile raw regex" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("^I have (\\d+) cucumbers$", testing.allocator);
    defer expr.deinit();

    try testing.expect(expr.is_raw_regex);
    try testing.expectEqual(@as(usize, 0), expr.captures.len);

    if (try expr.match("I have 42 cucumbers")) |result| {
        defer result.deinit();
        // Raw regex: capture groups become string args.
        try testing.expectEqual(@as(usize, 1), result.args.len);
        try testing.expect(std.mem.eql(u8, "42", result.args[0].string));
    } else {
        return error.TestExpectedMatch;
    }
}

test "compile cucumber expression - multiple parameters" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("{word} has {int} items worth {float}", testing.allocator);
    defer expr.deinit();

    try testing.expectEqual(@as(usize, 3), expr.captures.len);

    if (try expr.match("alice has 10 items worth 99.5")) |result| {
        defer result.deinit();
        try testing.expectEqual(@as(usize, 3), result.args.len);
        try testing.expect(std.mem.eql(u8, "alice", result.args[0].string));
        try testing.expectEqual(@as(i64, 10), result.args[1].int);
        try testing.expectEqual(@as(f64, 99.5), result.args[2].float);
    } else {
        return error.TestExpectedMatch;
    }
}

test "malformed expression - unclosed parameter" {
    const result = compile("I have {int cucumbers", testing.allocator);
    try testing.expectError(error.InvalidExpression, result);
}

test "malformed expression - unclosed optional" {
    const result = compile("I have cucumber(s", testing.allocator);
    try testing.expectError(error.InvalidExpression, result);
}

test "float parameter matches plain integer" {
    if (!has_regex) return error.SkipZigTest;
    var expr = try compile("I have {float} kg", testing.allocator);
    defer expr.deinit();

    if (try expr.match("I have 42 kg")) |result| {
        defer result.deinit();
        try testing.expectEqual(@as(f64, 42.0), result.args[0].float);
    } else {
        return error.TestExpectedMatch;
    }
}
