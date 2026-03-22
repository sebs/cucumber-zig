# Development

## Prerequisites

This project requires **Zig 0.14.0**. We use [zvm](https://github.com/marler182/zigvm) (Zig Version Manager) to manage the Zig toolchain.

### Installing zvm

```sh
curl -sL https://github.com/marler182/zigvm/releases/latest/download/zigvm-x86_64-macos -o zigvm
chmod +x zigvm
./zigvm install 0.14.0
./zigvm use 0.14.0
```

Or via Homebrew:

```sh
brew install zigvm
zvm install 0.14.0
zvm use 0.14.0
```

### Verifying

```sh
zig version
# Should print: 0.14.0
```

If your terminal shows a different version, ensure `~/.zvm/bin` is in your `PATH` before any system-installed Zig.

## Building and running

```sh
zig build                          # build the library and example
zig build test --summary all       # run all 146 tests
zig build run                      # run the banking example
```

If tests produce no output, add `--summary all` to see results. If you get stale build errors after switching branches or changing build config, clear the cache first:

```sh
rm -rf .zig-cache zig-out
zig build test --summary all
```

## Project structure

```
src/
  cucumber.zig              Root module — public API re-exports
  types.zig                 Core types: StepArg, DataTable, Pickle, etc.
  regex.zig                 Minimal NFA regex engine (Pike VM)
  expression.zig            Cucumber Expression compiler
  tag_expression.zig        Boolean tag expression parser
  step_registry.zig         Step definition storage and matching
  hooks.zig                 Hook registration and lifecycle
  runner.zig                Generic Runner(WorldType) orchestrator
  snippet.zig               Undefined step snippet generator
  Formatter.zig             Type-erased formatter interface (vtable)
  formatters/
    pretty.zig              Colored terminal formatter
    progress.zig            Compact CI formatter
    junit.zig               JUnit XML formatter
    json.zig                Legacy JSON formatter
    messages.zig            Cucumber Messages NDJSON formatter
  *_test.zig                Test files (extracted from source modules)

example/
  features/                 Gherkin feature files (banking domain)
  steps/                    Step definitions
  world.zig                 World struct (account management)
  main.zig                  Entry point wiring cucumber-zig
```

## Testing

Tests are separate `*_test.zig` files alongside their source modules, discovered via the root test block in `src/cucumber.zig`.

```sh
zig build test --summary all       # run all tests with output
```

The test suite covers:
- Unit tests for each subsystem (regex, expressions, tags, hooks, registry, runner, formatters, snippets, types)
- Conformance tests against the official [cucumber/cucumber-expressions](https://github.com/cucumber/cucumber-expressions) test suite

**Note:** `zig build test` without `--summary all` exits silently on success. Always use `--summary all` to see results.

## Design notes

- **No external dependencies** — the regex engine is built-in (NFA/Pike VM)
- **Arena allocator per scenario** — all scenario-scoped allocations freed in one shot
- **Generic `Runner(WorldType)`** — comptime detects `init`/`deinit` on the World type
- **Formatter vtable** — type-erased interface using `@hasDecl` for optional callbacks
- **Cucumber Expressions compiled to regex** — two-phase approach: identify alternation groups, then compile each fragment
