const std = @import("std");
const testing = std.testing;
const Regex = @import("regex.zig").Regex;

test "1. literal matching" {
    var re = try Regex.compile("hello", testing.allocator);
    defer re.deinit(testing.allocator);

    const caps = (try re.match("hello", testing.allocator)).?;
    defer testing.allocator.free(caps);
    try testing.expectEqualStrings("hello", caps[0].?);

    try testing.expect(re.isMatch("hello"));
    try testing.expect(!re.isMatch("world"));
}

test "2. character class \\d+" {
    var re = try Regex.compile("\\d+", testing.allocator);
    defer re.deinit(testing.allocator);

    const caps = (try re.match("abc123def", testing.allocator)).?;
    defer testing.allocator.free(caps);
    try testing.expectEqualStrings("123", caps[0].?);
}

test "3. capture groups" {
    var re = try Regex.compile("(\\d+) (\\w+)", testing.allocator);
    defer re.deinit(testing.allocator);

    const caps = (try re.match("42 abc", testing.allocator)).?;
    defer testing.allocator.free(caps);
    try testing.expectEqualStrings("42 abc", caps[0].?);
    try testing.expectEqualStrings("42", caps[1].?);
    try testing.expectEqualStrings("abc", caps[2].?);
}

test "4. alternation" {
    var re = try Regex.compile("cat|dog", testing.allocator);
    defer re.deinit(testing.allocator);

    {
        const caps = (try re.match("cat", testing.allocator)).?;
        defer testing.allocator.free(caps);
        try testing.expectEqualStrings("cat", caps[0].?);
    }
    {
        const caps = (try re.match("dog", testing.allocator)).?;
        defer testing.allocator.free(caps);
        try testing.expectEqualStrings("dog", caps[0].?);
    }
    try testing.expect(!re.isMatch("bird"));
}

test "5. quantifiers a*b+c?" {
    var re = try Regex.compile("a*b+c?", testing.allocator);
    defer re.deinit(testing.allocator);

    {
        const caps = (try re.match("b", testing.allocator)).?;
        defer testing.allocator.free(caps);
        try testing.expectEqualStrings("b", caps[0].?);
    }
    {
        const caps = (try re.match("aaabbc", testing.allocator)).?;
        defer testing.allocator.free(caps);
        try testing.expectEqualStrings("aaabbc", caps[0].?);
    }
    {
        const caps = (try re.match("bb", testing.allocator)).?;
        defer testing.allocator.free(caps);
        try testing.expectEqualStrings("bb", caps[0].?);
    }
    {
        const caps = (try re.match("bc", testing.allocator)).?;
        defer testing.allocator.free(caps);
        try testing.expectEqualStrings("bc", caps[0].?);
    }
    try testing.expect(!re.isMatch("ac"));
}

test "6. anchored match ^hello$" {
    var re = try Regex.compile("^hello$", testing.allocator);
    defer re.deinit(testing.allocator);

    try testing.expect(re.isMatch("hello"));
    try testing.expect(!re.isMatch("say hello"));
    try testing.expect(!re.isMatch("hello world"));
}

test "7. negated character class [^abc]+" {
    var re = try Regex.compile("[^abc]+", testing.allocator);
    defer re.deinit(testing.allocator);

    {
        const caps = (try re.match("xyz", testing.allocator)).?;
        defer testing.allocator.free(caps);
        try testing.expectEqualStrings("xyz", caps[0].?);
    }
    {
        const caps = (try re.match("aaxyz", testing.allocator)).?;
        defer testing.allocator.free(caps);
        try testing.expectEqualStrings("xyz", caps[0].?);
    }
}

test "8. optional group colou?r" {
    var re = try Regex.compile("colou?r", testing.allocator);
    defer re.deinit(testing.allocator);

    try testing.expect(re.isMatch("color"));
    try testing.expect(re.isMatch("colour"));
    try testing.expect(!re.isMatch("colr"));
}

test "9. escaped characters \\." {
    var re = try Regex.compile("\\.", testing.allocator);
    defer re.deinit(testing.allocator);

    try testing.expect(re.isMatch("a.b"));
    try testing.expect(!re.isMatch("abc"));
}

test "non-capture group (?:...)" {
    var re = try Regex.compile("(?:ab)+", testing.allocator);
    defer re.deinit(testing.allocator);

    const caps = (try re.match("ababab", testing.allocator)).?;
    defer testing.allocator.free(caps);
    try testing.expectEqualStrings("ababab", caps[0].?);
    try testing.expect(caps.len == 1);
}

test "dot matches any except newline" {
    var re = try Regex.compile("a.b", testing.allocator);
    defer re.deinit(testing.allocator);

    try testing.expect(re.isMatch("aXb"));
    try testing.expect(re.isMatch("a b"));
    try testing.expect(!re.isMatch("a\nb"));
}

test "character class range [a-z]+" {
    var re = try Regex.compile("[a-z]+", testing.allocator);
    defer re.deinit(testing.allocator);

    const caps = (try re.match("Hello World", testing.allocator)).?;
    defer testing.allocator.free(caps);
    try testing.expectEqualStrings("ello", caps[0].?);
}

test "complex cucumber-style pattern" {
    var re = try Regex.compile("^I have (\\d+) cucumbers in my (\\w+)$", testing.allocator);
    defer re.deinit(testing.allocator);

    const caps = (try re.match("I have 42 cucumbers in my belly", testing.allocator)).?;
    defer testing.allocator.free(caps);
    try testing.expectEqualStrings("I have 42 cucumbers in my belly", caps[0].?);
    try testing.expectEqualStrings("42", caps[1].?);
    try testing.expectEqualStrings("belly", caps[2].?);

    try testing.expect(!re.isMatch("I have many cucumbers in my belly"));
}

test "compile error: trailing backslash" {
    const result = Regex.compile("abc\\", testing.allocator);
    try testing.expectError(error.TrailingBackslash, result);
}

test "compile error: unmatched paren" {
    const result = Regex.compile("(abc", testing.allocator);
    try testing.expectError(error.UnmatchedParen, result);
}

test "compile error: unmatched bracket" {
    const result = Regex.compile("[abc", testing.allocator);
    try testing.expectError(error.UnmatchedBracket, result);
}

test "empty pattern matches empty string" {
    var re = try Regex.compile("", testing.allocator);
    defer re.deinit(testing.allocator);

    const caps = (try re.match("", testing.allocator)).?;
    defer testing.allocator.free(caps);
    try testing.expectEqualStrings("", caps[0].?);
}

test "greedy matching: a+ captures all a's" {
    var re = try Regex.compile("a+", testing.allocator);
    defer re.deinit(testing.allocator);

    const caps = (try re.match("aaa", testing.allocator)).?;
    defer testing.allocator.free(caps);
    try testing.expectEqualStrings("aaa", caps[0].?);
}
