# cucumber-zig

A full [Cucumber](https://cucumber.io/) BDD framework for Zig. Takes Pickles (flattened test cases from a Gherkin parser) and runs them against Zig step definitions with Cucumber Expression matching, scenario lifecycle management, hooks, tag filtering, and multiple output formatters.

## Features

- **Cucumber Expressions** — `{int}`, `{float}`, `{word}`, `{string}`, `{}`, optional text `(s)`, alternation `a/b`
- **Step registry** — runtime registration with `given`, `when`, `then` + ambiguity detection
- **World lifecycle** — generic `Runner(WorldType)` with comptime `init`/`deinit` detection, arena allocator per scenario
- **Hooks** — `BeforeAll`, `Before`, `BeforeStep`, `AfterStep`, `After`, `AfterAll` with tag filtering and ordering
- **Tag expressions** — boolean expressions over tags: `@smoke and not @slow`
- **Formatters** — Pretty (terminal), Progress (CI dots), JUnit XML, JSON, Cucumber Messages (NDJSON)
- **Snippet generation** — generates Zig function stubs for undefined steps
- **Built-in regex engine** — minimal NFA/Pike VM, no external dependencies

## Quick start

```zig
const cucumber = @import("cucumber-zig");

const World = struct {
    result: i64 = 0,
};

fn given_value(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
    const world: *World = @ptrCast(@alignCast(ctx));
    world.result = try args[0].asInt();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var registry = cucumber.StepRegistry.init(allocator);
    defer registry.deinit();
    try registry.given("I have {int} cucumbers", given_value);

    var hooks = cucumber.HookRegistry.init(allocator);
    defer hooks.deinit();

    var runner = cucumber.Runner(World).init(allocator, &registry, &hooks);
    defer runner.deinit();

    // Add a formatter for terminal output
    var pretty = cucumber.formatters.Pretty.init(std.io.getStdOut().writer().any());
    try runner.addFormatter(pretty.formatter());

    const summary = try runner.run(pickles); // pickles from your Gherkin parser
    if (summary.failed > 0) std.process.exit(1);
}
```

## Step definitions

Register steps with Cucumber Expression patterns:

```zig
try registry.given("I have {int} cucumbers", myStep);
try registry.when("I eat {int} cucumber(s)", eatStep);
try registry.then("I should have {int} cucumber(s) left", verifyStep);
```

Step functions receive an opaque world pointer and extracted arguments:

```zig
fn myStep(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
    const world: *World = @ptrCast(@alignCast(ctx));
    const count = try args[0].asInt();   // i64
    world.cucumbers = count;
}
```

Supported parameter types:

| Expression | Zig type | Example |
|---|---|---|
| `{int}` | `i64` | `42`, `-7` |
| `{float}` | `f64` | `3.14`, `.5`, `42` |
| `{word}` | `[]const u8` | `alice` (no spaces) |
| `{string}` | `[]const u8` | `"hello"` or `'hello'` (strips quotes) |
| `{}` | `[]const u8` | anything (anonymous) |

## Hooks

```zig
try hooks.addBefore("setup", null, 0, myBeforeHook);
try hooks.addAfter("cleanup", null, 0, myAfterHook);
try hooks.addBefore("smoke only", "@smoke", 0, smokeSetup); // tag-filtered
try hooks.addBeforeAll("global setup", 0, globalSetup);
```

- `Before`/`After` hooks receive `(*anyopaque, ScenarioInfo)` and run per-scenario
- `BeforeAll`/`AfterAll` hooks receive no arguments and run once per suite
- `Before` hooks run in ascending order; `After` hooks run in descending (reverse) order

## Tag filtering

Filter scenarios by tag expression:

```zig
try runner.setTagFilter("@smoke and not @slow");
```

Supports `and`, `or`, `not`, and parentheses with correct precedence.

## Formatters

Attach one or more formatters before running:

```zig
// Terminal output with colors
var pretty = cucumber.formatters.Pretty.init(stdout.writer().any());
try runner.addFormatter(pretty.formatter());

// JUnit XML for CI
var junit = cucumber.formatters.JUnit.init(allocator, file.writer().any());
try runner.addFormatter(junit.formatter());
```

| Formatter | Output |
|---|---|
| `Pretty` | Colored terminal output with step symbols |
| `Progress` | Compact `.F?P-` per step |
| `JUnit` | JUnit XML for CI integration |
| `Json` | Legacy Cucumber JSON format |
| `Messages` | Cucumber Messages NDJSON |

## Building

```sh
zig build          # build the library
zig build test     # run all 146 tests
```

Requires Zig 0.13+.

## License

MIT
