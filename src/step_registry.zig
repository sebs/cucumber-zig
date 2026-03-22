const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const Expression = @import("expression.zig");

// ── Step Definition Registry ──
//
// Manages the mapping from step text (Given/When/Then) to Zig functions.
//
// Each registered step definition consists of:
//   - A Cucumber Expression (or raw regex) pattern
//   - A keyword (given/when/then/any) for diagnostics
//   - A step function to invoke
//   - An optional source location for error reporting
//
// At registration time the pattern is compiled via Expression.compile.
// At runtime findMatch() tries all registered definitions against the
// step text and returns the unique match or an error if ambiguous.

pub const StepFn = *const fn (world: *anyopaque, args: types.StepArgs) anyerror!void;

pub const StepDef = struct {
    pattern: []const u8,
    keyword: types.Keyword,
    func: StepFn,
    location: ?types.SourceLocation,
    expression: Expression.CompiledExpression,
};

pub const MatchedStep = struct {
    step_def: *const StepDef,
    args: []const types.StepArg,
    match_result: Expression.MatchResult,
};

pub const StepRegistry = struct {
    steps: std.ArrayList(StepDef),
    allocator: Allocator,

    pub fn init(allocator: Allocator) StepRegistry {
        return .{
            .steps = std.ArrayList(StepDef).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StepRegistry) void {
        for (self.steps.items) |*step_def| {
            var expr = step_def.expression;
            expr.deinit();
        }
        self.steps.deinit();
    }

    /// Register a Given step definition.
    pub fn given(self: *StepRegistry, pattern: []const u8, func: StepFn) !void {
        try self.step(.given, pattern, func);
    }

    /// Register a When step definition.
    pub fn when(self: *StepRegistry, pattern: []const u8, func: StepFn) !void {
        try self.step(.when, pattern, func);
    }

    /// Register a Then step definition.
    pub fn then(self: *StepRegistry, pattern: []const u8, func: StepFn) !void {
        try self.step(.then, pattern, func);
    }

    /// Register a step definition with an explicit keyword.
    pub fn step(self: *StepRegistry, keyword: types.Keyword, pattern: []const u8, func: StepFn) !void {
        const expr = try Expression.compile(pattern, self.allocator);
        try self.steps.append(.{
            .pattern = pattern,
            .keyword = keyword,
            .func = func,
            .location = null,
            .expression = expr,
        });
    }

    /// Find the step definition matching the given text.
    ///
    /// Returns error.AmbiguousStep if multiple definitions match.
    /// Returns null if no definition matches.
    pub fn findMatch(self: *const StepRegistry, step_text: []const u8, allocator: Allocator) !?MatchedStep {
        var found: ?MatchedStep = null;

        for (self.steps.items) |*step_def| {
            if (try step_def.expression.match(step_text)) |match_result| {
                if (found != null) {
                    // Clean up both match results before returning error.
                    var prev = found.?.match_result;
                    prev.deinit();
                    var cur = match_result;
                    cur.deinit();
                    return error.AmbiguousStep;
                }
                found = .{
                    .step_def = step_def,
                    .args = match_result.args,
                    .match_result = match_result,
                };
            }
        }

        _ = allocator; // allocator available for future use
        return found;
    }

    /// Check all step definitions for ambiguity against each other.
    ///
    /// This is a static check that compiles a set of representative
    /// test strings and checks if any two patterns would both match.
    /// Note: this is a best-effort heuristic. True ambiguity detection
    /// for arbitrary regexes is undecidable, so this method checks
    /// whether any registered pattern string matches another definition.
    pub fn checkAmbiguities(self: *const StepRegistry) !void {
        const items = self.steps.items;
        for (items, 0..) |*def_i, i| {
            for (items[i + 1 ..]) |*def_j| {
                // Check if pattern i's text matches definition j.
                if (try def_j.expression.match(def_i.pattern)) |*result_| {
                    var result = result_;
                    result.deinit();
                    return error.AmbiguousStep;
                }
                // Check if pattern j's text matches definition i.
                if (try def_i.expression.match(def_j.pattern)) |*result_| {
                    var result = result_;
                    result.deinit();
                    return error.AmbiguousStep;
                }
            }
        }
    }

    /// Return the number of registered step definitions.
    pub fn count(self: *const StepRegistry) usize {
        return self.steps.items.len;
    }
};
