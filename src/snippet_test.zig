const std = @import("std");
const testing = std.testing;
const SnippetGenerator = @import("snippet.zig").SnippetGenerator;

test "simple step with no parameters" {
    const snippet = try SnippetGenerator.generate(
        "I am on the homepage",
        "When",
        false,
        false,
        testing.allocator,
    );
    defer testing.allocator.free(snippet);

    const expected =
        \\// TODO: Implement this step
        \\// When I am on the homepage
        \\fn when_i_am_on_the_homepage(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
        \\    _ = ctx;
        \\    _ = args;
        \\    return error.Pending;
        \\}
    ;
    try testing.expectEqualStrings(expected, snippet);
}

test "step with integer parameter" {
    const snippet = try SnippetGenerator.generate(
        "I have 42 cucumbers",
        "Given",
        false,
        false,
        testing.allocator,
    );
    defer testing.allocator.free(snippet);

    const expected =
        \\// TODO: Implement this step
        \\// Given I have 42 cucumbers
        \\fn given_i_have_int_cucumbers(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
        \\    _ = ctx;
        \\    _ = args;
        \\    // args[0].int == i64 (e.g., 42)
        \\    return error.Pending;
        \\}
    ;
    try testing.expectEqualStrings(expected, snippet);
}

test "step with string parameter" {
    const snippet = try SnippetGenerator.generate(
        "I log in as \"alice\"",
        "When",
        false,
        false,
        testing.allocator,
    );
    defer testing.allocator.free(snippet);

    const expected =
        \\// TODO: Implement this step
        \\// When I log in as "alice"
        \\fn when_i_log_in_as_string(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
        \\    _ = ctx;
        \\    _ = args;
        \\    // args[0].string == []const u8 (e.g., alice)
        \\    return error.Pending;
        \\}
    ;
    try testing.expectEqualStrings(expected, snippet);
}

test "step with multiple parameters" {
    const snippet = try SnippetGenerator.generate(
        "I have 42 cucumbers in my \"garden\"",
        "Given",
        false,
        false,
        testing.allocator,
    );
    defer testing.allocator.free(snippet);

    const expected =
        \\// TODO: Implement this step
        \\// Given I have 42 cucumbers in my "garden"
        \\fn given_i_have_int_cucumbers_in_my_string(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
        \\    _ = ctx;
        \\    _ = args;
        \\    // args[0].int == i64 (e.g., 42)
        \\    // args[1].string == []const u8 (e.g., garden)
        \\    return error.Pending;
        \\}
    ;
    try testing.expectEqualStrings(expected, snippet);
}

test "step with table" {
    const snippet = try SnippetGenerator.generate(
        "the following users exist",
        "Given",
        true,
        false,
        testing.allocator,
    );
    defer testing.allocator.free(snippet);

    const expected =
        \\// TODO: Implement this step
        \\// Given the following users exist
        \\fn given_the_following_users_exist(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
        \\    _ = ctx;
        \\    _ = args;
        \\    // args[0].table == DataTable
        \\    return error.Pending;
        \\}
    ;
    try testing.expectEqualStrings(expected, snippet);
}

test "step with doc string" {
    const snippet = try SnippetGenerator.generate(
        "the page content is",
        "Then",
        false,
        true,
        testing.allocator,
    );
    defer testing.allocator.free(snippet);

    const expected =
        \\// TODO: Implement this step
        \\// Then the page content is
        \\fn then_the_page_content_is(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
        \\    _ = ctx;
        \\    _ = args;
        \\    // args[0].doc_string == DocString
        \\    return error.Pending;
        \\}
    ;
    try testing.expectEqualStrings(expected, snippet);
}

test "step with float parameter" {
    const snippet = try SnippetGenerator.generate(
        "the price is 3.14 dollars",
        "Given",
        false,
        false,
        testing.allocator,
    );
    defer testing.allocator.free(snippet);

    const expected =
        \\// TODO: Implement this step
        \\// Given the price is 3.14 dollars
        \\fn given_the_price_is_float_dollars(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
        \\    _ = ctx;
        \\    _ = args;
        \\    // args[0].float == f64 (e.g., 3.14)
        \\    return error.Pending;
        \\}
    ;
    try testing.expectEqualStrings(expected, snippet);
}

test "step with parameters and table" {
    const snippet = try SnippetGenerator.generate(
        "user \"bob\" has 5 items",
        "Given",
        true,
        false,
        testing.allocator,
    );
    defer testing.allocator.free(snippet);

    const expected =
        \\// TODO: Implement this step
        \\// Given user "bob" has 5 items
        \\fn given_user_string_has_int_items(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
        \\    _ = ctx;
        \\    _ = args;
        \\    // args[0].string == []const u8 (e.g., bob)
        \\    // args[1].int == i64 (e.g., 5)
        \\    // args[2].table == DataTable
        \\    return error.Pending;
        \\}
    ;
    try testing.expectEqualStrings(expected, snippet);
}

test "step with negative integer parameter" {
    const snippet = try SnippetGenerator.generate(
        "I have -5 cucumbers",
        "Given",
        false,
        false,
        testing.allocator,
    );
    defer testing.allocator.free(snippet);

    const expected =
        \\// TODO: Implement this step
        \\// Given I have -5 cucumbers
        \\fn given_i_have_int_cucumbers(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
        \\    _ = ctx;
        \\    _ = args;
        \\    // args[0].int == i64 (e.g., -5)
        \\    return error.Pending;
        \\}
    ;
    try testing.expectEqualStrings(expected, snippet);
}

test "step with float parameter detected from step text" {
    const snippet = try SnippetGenerator.generate(
        "the temperature is 3.14 degrees",
        "When",
        false,
        false,
        testing.allocator,
    );
    defer testing.allocator.free(snippet);

    const expected =
        \\// TODO: Implement this step
        \\// When the temperature is 3.14 degrees
        \\fn when_the_temperature_is_float_degrees(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
        \\    _ = ctx;
        \\    _ = args;
        \\    // args[0].float == f64 (e.g., 3.14)
        \\    return error.Pending;
        \\}
    ;
    try testing.expectEqualStrings(expected, snippet);
}
