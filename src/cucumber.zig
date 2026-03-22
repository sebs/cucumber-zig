//! cucumber-zig: A full Cucumber BDD framework for Zig.
//!
//! This library provides everything needed to run Gherkin feature files
//! against Zig step definitions: step matching via Cucumber Expressions,
//! scenario lifecycle with World management, hooks, tag filtering,
//! and multiple output formatters.
//!
//! ## Quick Start
//!
//! ```zig
//! const cucumber = @import("cucumber-zig");
//!
//! const World = struct {
//!     result: i32 = 0,
//! };
//!
//! fn given_value(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
//!     const world: *World = @ptrCast(@alignCast(ctx));
//!     world.result = try args[0].asInt();
//! }
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!     const allocator = gpa.allocator();
//!
//!     var registry = cucumber.StepRegistry.init(allocator);
//!     defer registry.deinit();
//!     try registry.given("I have {int} cucumbers", given_value);
//!
//!     var hooks = cucumber.HookRegistry.init(allocator);
//!     defer hooks.deinit();
//!
//!     var runner = cucumber.Runner(World).init(allocator, &registry, &hooks);
//!     defer runner.deinit();
//!
//!     const summary = try runner.run(pickles);
//!     if (summary.failed > 0) std.process.exit(1);
//! }
//! ```

const std = @import("std");

// ── Core types ──
pub const types = @import("types.zig");
pub const StepArg = types.StepArg;
pub const StepArgs = types.StepArgs;
pub const DataTable = types.DataTable;
pub const DocString = types.DocString;
pub const Keyword = types.Keyword;
pub const StepStatus = types.StepStatus;
pub const StepResult = types.StepResult;
pub const ScenarioInfo = types.ScenarioInfo;
pub const SourceLocation = types.SourceLocation;
pub const Pickle = types.Pickle;
pub const PickleStep = types.PickleStep;
pub const PickleTag = types.PickleTag;
pub const PickleTable = types.PickleTable;
pub const PickleTableRow = types.PickleTableRow;
pub const PickleTableCell = types.PickleTableCell;
pub const PickleDocString = types.PickleDocString;
pub const PickleStepArgument = types.PickleStepArgument;
pub const TestCaseInfo = types.TestCaseInfo;
pub const TestCaseResult = types.TestCaseResult;
pub const RunSummary = types.RunSummary;

// ── Regex engine ──
pub const Regex = @import("regex.zig").Regex;

// ── Cucumber Expressions ──
pub const Expression = @import("expression.zig");
pub const CompiledExpression = Expression.CompiledExpression;
pub const ParamType = Expression.ParamType;

// ── Tag expressions ──
pub const TagExpression = @import("tag_expression.zig").TagExpression;

// ── Step registry ──
const step_registry = @import("step_registry.zig");
pub const StepRegistry = step_registry.StepRegistry;
pub const StepDef = step_registry.StepDef;
pub const StepFn = step_registry.StepFn;
pub const MatchedStep = step_registry.MatchedStep;

// ── Hooks ──
const hooks_mod = @import("hooks.zig");
pub const HookRegistry = hooks_mod.HookRegistry;
pub const Hook = hooks_mod.Hook;
pub const SuiteHook = hooks_mod.SuiteHook;
pub const HookType = hooks_mod.HookType;
pub const HookFn = hooks_mod.HookFn;
pub const SuiteHookFn = hooks_mod.SuiteHookFn;

// ── Snippet generator ──
pub const SnippetGenerator = @import("snippet.zig").SnippetGenerator;

// ── Formatter interface ──
pub const Formatter = @import("Formatter.zig");

// ── Built-in formatters ──
pub const formatters = struct {
    pub const Pretty = @import("formatters/pretty.zig");
    pub const Progress = @import("formatters/progress.zig");
    pub const JUnit = @import("formatters/junit.zig");
    pub const Json = @import("formatters/json.zig");
    pub const Messages = @import("formatters/messages.zig");
};

// ── Test runner ──
pub const Runner = @import("runner.zig").Runner;

// ── Re-export common error set ──
pub const CucumberError = types.CucumberError;

// ── Tests ──
test {
    // Run tests from all submodules
    @import("std").testing.refAllDecls(@This());

    // Test files extracted from source modules
    _ = @import("regex_test.zig");
    _ = @import("expression_test.zig");
    _ = @import("expression_conformance_test.zig");
    _ = @import("tag_expression_test.zig");
    _ = @import("step_registry_test.zig");
    _ = @import("hooks_test.zig");
    _ = @import("snippet_test.zig");
    _ = @import("types_test.zig");
    _ = @import("Formatter_test.zig");
    _ = @import("runner_test.zig");
    _ = @import("formatters/pretty_test.zig");
    _ = @import("formatters/progress_test.zig");
    _ = @import("formatters/junit_test.zig");
    _ = @import("formatters/json_test.zig");
    _ = @import("formatters/messages_test.zig");
}
