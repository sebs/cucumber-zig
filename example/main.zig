const std = @import("std");
const cucumber = @import("cucumber");
const World = @import("world.zig").World;
const account_steps = @import("steps/account_steps.zig");

/// In a real project, pickles would come from parsing .feature files with a
/// Gherkin parser. Here we construct them manually to demonstrate the framework.
fn buildPickles(allocator: std.mem.Allocator) ![]const cucumber.Pickle {
    var pickles = std.ArrayList(cucumber.Pickle).init(allocator);

    // Scenario: Initial balance is zero
    {
        const steps = try allocator.dupe(cucumber.PickleStep, &.{
            .{ .text = "a new account for \"Alice\"", .keyword = "Given " },
            .{ .text = "the balance should be 0", .keyword = "Then " },
        });
        try pickles.append(.{
            .id = "1",
            .name = "Initial balance is zero",
            .uri = "features/account.feature",
            .line = 8,
            .steps = steps,
            .tags = &.{},
        });
    }

    // Scenario: Depositing money
    {
        const steps = try allocator.dupe(cucumber.PickleStep, &.{
            .{ .text = "a new account for \"Alice\"", .keyword = "Given " },
            .{ .text = "I deposit 100", .keyword = "When " },
            .{ .text = "the balance should be 100", .keyword = "Then " },
        });
        try pickles.append(.{
            .id = "2",
            .name = "Depositing money",
            .uri = "features/account.feature",
            .line = 11,
            .steps = steps,
            .tags = &.{},
        });
    }

    // Scenario: Withdrawing money
    {
        const steps = try allocator.dupe(cucumber.PickleStep, &.{
            .{ .text = "a new account for \"Alice\"", .keyword = "Given " },
            .{ .text = "I deposit 500", .keyword = "Given " },
            .{ .text = "I withdraw 200", .keyword = "When " },
            .{ .text = "the balance should be 300", .keyword = "Then " },
        });
        try pickles.append(.{
            .id = "3",
            .name = "Withdrawing money",
            .uri = "features/account.feature",
            .line = 15,
            .steps = steps,
            .tags = &.{},
        });
    }

    // Scenario: Cannot withdraw more than balance
    {
        const steps = try allocator.dupe(cucumber.PickleStep, &.{
            .{ .text = "a new account for \"Alice\"", .keyword = "Given " },
            .{ .text = "I deposit 100", .keyword = "Given " },
            .{ .text = "I try to withdraw 200", .keyword = "When " },
            .{ .text = "the withdrawal should be declined", .keyword = "Then " },
            .{ .text = "the balance should be 100", .keyword = "Then " },
        });
        try pickles.append(.{
            .id = "4",
            .name = "Cannot withdraw more than balance",
            .uri = "features/account.feature",
            .line = 20,
            .steps = steps,
            .tags = &.{},
        });
    }

    // Scenario: Multiple deposits (@smoke)
    {
        const tags = try allocator.dupe(cucumber.PickleTag, &.{
            .{ .name = "@smoke" },
        });
        const steps = try allocator.dupe(cucumber.PickleStep, &.{
            .{ .text = "a new account for \"Alice\"", .keyword = "Given " },
            .{ .text = "I deposit 100", .keyword = "When " },
            .{ .text = "I deposit 250", .keyword = "When " },
            .{ .text = "I deposit 50", .keyword = "When " },
            .{ .text = "the balance should be 400", .keyword = "Then " },
        });
        try pickles.append(.{
            .id = "5",
            .name = "Multiple deposits",
            .uri = "features/account.feature",
            .line = 27,
            .steps = steps,
            .tags = tags,
        });
    }

    // Scenario: Transfer between two accounts
    {
        const steps = try allocator.dupe(cucumber.PickleStep, &.{
            .{ .text = "a new account for \"Alice\"", .keyword = "Given " },
            .{ .text = "a new account for \"Bob\"", .keyword = "Given " },
            .{ .text = "\"Alice\" has a balance of 1000", .keyword = "Given " },
            .{ .text = "\"Alice\" transfers 300 to \"Bob\"", .keyword = "When " },
            .{ .text = "\"Alice\" should have a balance of 700", .keyword = "Then " },
            .{ .text = "\"Bob\" should have a balance of 300", .keyword = "Then " },
        });
        try pickles.append(.{
            .id = "6",
            .name = "Transfer between two accounts",
            .uri = "features/transfer.feature",
            .line = 5,
            .steps = steps,
            .tags = &.{},
        });
    }

    // Scenario: Transfer fails with insufficient funds
    {
        const steps = try allocator.dupe(cucumber.PickleStep, &.{
            .{ .text = "a new account for \"Alice\"", .keyword = "Given " },
            .{ .text = "a new account for \"Bob\"", .keyword = "Given " },
            .{ .text = "\"Alice\" has a balance of 100", .keyword = "Given " },
            .{ .text = "\"Alice\" tries to transfer 500 to \"Bob\"", .keyword = "When " },
            .{ .text = "the transfer should be declined", .keyword = "Then " },
            .{ .text = "\"Alice\" should have a balance of 100", .keyword = "Then " },
            .{ .text = "\"Bob\" should have a balance of 0", .keyword = "Then " },
        });
        try pickles.append(.{
            .id = "7",
            .name = "Transfer fails with insufficient funds",
            .uri = "features/transfer.feature",
            .line = 14,
            .steps = steps,
            .tags = &.{},
        });
    }

    return pickles.toOwnedSlice();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Set up step registry
    var registry = cucumber.StepRegistry.init(allocator);
    defer registry.deinit();
    try account_steps.register(&registry);

    // Set up hooks (none for this example)
    var hooks = cucumber.HookRegistry.init(allocator);
    defer hooks.deinit();

    // Set up runner
    var runner = cucumber.Runner(World).init(allocator, &registry, &hooks);
    defer runner.deinit();

    // Add pretty formatter for terminal output
    const stdout = std.io.getStdOut().writer().any();
    var pretty = cucumber.formatters.Pretty.init(stdout);
    try runner.addFormatter(pretty.formatter());

    // Build pickles (normally from a Gherkin parser)
    const pickles = try buildPickles(allocator);
    defer {
        for (pickles) |p| {
            allocator.free(p.steps);
            allocator.free(p.tags);
        }
        allocator.free(pickles);
    }

    // Run!
    const summary = try runner.run(pickles);

    // Exit with failure code if any scenarios failed
    if (summary.failed > 0 or summary.undefined > 0) {
        std.process.exit(1);
    }
}
