const std = @import("std");
const types = @import("types.zig");
const StepRegistry = @import("step_registry.zig").StepRegistry;
const HookRegistry = @import("hooks.zig").HookRegistry;
const TagExpression = @import("tag_expression.zig").TagExpression;
const Fmt = @import("Formatter.zig");
const SnippetGenerator = @import("snippet.zig").SnippetGenerator;

const Allocator = std.mem.Allocator;

/// A generic test runner parameterised on the World type that is threaded
/// through every step and hook invocation.  The World is created fresh for
/// each Pickle (scenario), giving every scenario an isolated context.
pub fn Runner(comptime WorldType: type) type {
    return struct {
        const Self = @This();

        step_registry: *StepRegistry,
        hook_registry: *HookRegistry,
        formatters: std.ArrayList(Fmt),
        tag_filter: ?TagExpression,
        allocator: Allocator,
        snippet_buf: std.ArrayList([]const u8),
        result_slices: std.ArrayList([]const types.StepResult),

        pub fn init(
            allocator: Allocator,
            step_registry: *StepRegistry,
            hook_registry: *HookRegistry,
        ) Self {
            return .{
                .step_registry = step_registry,
                .hook_registry = hook_registry,
                .formatters = std.ArrayList(Fmt).init(allocator),
                .tag_filter = null,
                .allocator = allocator,
                .snippet_buf = std.ArrayList([]const u8).init(allocator),
                .result_slices = std.ArrayList([]const types.StepResult).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.tag_filter) |*tf| {
                tf.deinit();
            }
            for (self.snippet_buf.items) |s| {
                self.allocator.free(s);
            }
            self.snippet_buf.deinit();
            for (self.result_slices.items) |s| {
                self.allocator.free(s);
            }
            self.result_slices.deinit();
            self.formatters.deinit();
        }

        pub fn addFormatter(self: *Self, formatter: Fmt) !void {
            try self.formatters.append(formatter);
        }

        pub fn setTagFilter(self: *Self, expression: []const u8) !void {
            if (self.tag_filter) |*tf| {
                tf.deinit();
            }
            self.tag_filter = try TagExpression.parse(expression, self.allocator);
        }

        // ── Formatter notification helpers ──────────────────────

        fn notifyTestRunStarted(self: *Self) void {
            for (self.formatters.items) |f| f.onTestRunStarted();
        }

        fn notifyTestRunFinished(self: *Self, summary: types.RunSummary) void {
            for (self.formatters.items) |f| f.onTestRunFinished(summary);
        }

        fn notifyTestCaseStarted(self: *Self, info: types.TestCaseInfo) void {
            for (self.formatters.items) |f| f.onTestCaseStarted(info);
        }

        fn notifyTestCaseFinished(self: *Self, result: types.TestCaseResult) void {
            for (self.formatters.items) |f| f.onTestCaseFinished(result);
        }

        fn notifyTestStepStarted(self: *Self, pickle: types.Pickle, step_index: usize) void {
            for (self.formatters.items) |f| f.onTestStepStarted(pickle, step_index);
        }

        fn notifyTestStepFinished(self: *Self, pickle: types.Pickle, step_index: usize, result: types.StepResult) void {
            for (self.formatters.items) |f| f.onTestStepFinished(pickle, step_index, result);
        }

        // ── Public entry point ──────────────────────────────────

        /// Run all pickles and return an aggregate summary.
        pub fn run(self: *Self, pickles: []const types.Pickle) !types.RunSummary {
            var summary = types.RunSummary{};

            var run_timer = std.time.Timer.start() catch null;

            // Run BeforeAll suite hooks.
            var suite_setup_failed = false;
            const before_all = self.hook_registry.getBeforeAllHooks();
            for (before_all) |hook| {
                hook.func() catch {
                    suite_setup_failed = true;
                    break;
                };
            }

            self.notifyTestRunStarted();

            for (pickles) |pickle| {
                if (suite_setup_failed) {
                    // BeforeAll hook failed — mark every scenario as failed.
                    summary.total += 1;
                    summary.failed += 1;
                    continue;
                }
                const result = try self.runPickle(pickle);
                try self.result_slices.append(result.step_results);
                summary.total += 1;
                switch (result.status) {
                    .passed => summary.passed += 1,
                    .failed => summary.failed += 1,
                    .skipped => summary.skipped += 1,
                    .undefined => summary.undefined += 1,
                    .pending => summary.pending += 1,
                }
                summary.duration_ns += result.duration_ns;
            }

            // If we couldn't start the timer, fall back to summed durations.
            if (run_timer) |*timer| {
                summary.duration_ns = timer.read();
            }

            // Run AfterAll suite hooks.
            // Teardown errors are intentionally swallowed — failing here should
            // not override the real test results.
            const after_all = self.hook_registry.getAfterAllHooks();
            for (after_all) |hook| {
                hook.func() catch {};
            }

            self.notifyTestRunFinished(summary);

            return summary;
        }

        // ── Single pickle execution ─────────────────────────────

        /// Run a single pickle (scenario).
        fn runPickle(self: *Self, pickle: types.Pickle) !types.TestCaseResult {
            // 1. Check tag filter — skip if tags don't match.
            if (self.tag_filter) |*tf| {
                const tag_strings = try self.extractTagStrings(pickle.tags, self.allocator);
                defer self.allocator.free(tag_strings);
                if (!tf.evaluate(tag_strings)) {
                    const result = types.TestCaseResult{
                        .pickle = pickle,
                        .step_results = &.{},
                        .status = .skipped,
                        .duration_ns = 0,
                    };
                    self.notifyTestCaseStarted(.{ .pickle = pickle, .attempt = 0 });
                    self.notifyTestCaseFinished(result);
                    return result;
                }
            }

            // 2. Create a scenario-level arena allocator.
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const scenario_alloc = arena.allocator();

            // 3. Allocate and initialise World.
            var world = if (@hasDecl(WorldType, "init"))
                try WorldType.init(scenario_alloc)
            else
                std.mem.zeroes(WorldType);

            // 4. Extract tag strings for hook filtering.
            const tag_strings = try self.extractTagStrings(pickle.tags, scenario_alloc);

            // Build ScenarioInfo for hooks (mutable so status can be updated).
            var scenario_info = types.ScenarioInfo{
                .name = pickle.name,
                .tags = tag_strings,
                .uri = pickle.uri,
                .line = pickle.line,
                .status = null,
            };

            self.notifyTestCaseStarted(.{ .pickle = pickle, .attempt = 0 });

            var case_timer = std.time.Timer.start() catch null;

            // 5. Run Before hooks.
            var scenario_failed = false;
            const before_hooks = self.hook_registry.getBeforeHooks(tag_strings);
            for (before_hooks) |hook| {
                hook.func(@ptrCast(&world), scenario_info) catch {
                    scenario_failed = true;
                    break;
                };
            }

            // 6. Execute each PickleStep.
            // Use the main allocator so results survive arena cleanup.
            var step_results = std.ArrayList(types.StepResult).init(self.allocator);
            errdefer step_results.deinit();
            var overall_status: types.StepStatus = .passed;
            var should_skip = scenario_failed;

            if (scenario_failed) {
                overall_status = .failed;
            }

            for (pickle.steps, 0..) |step, step_index| {
                self.notifyTestStepStarted(pickle, step_index);

                var step_result: types.StepResult = undefined;

                if (should_skip) {
                    step_result = .{
                        .status = .skipped,
                        .duration_ns = 0,
                        .step_text = step.text,
                        .step_keyword = step.keyword,
                    };
                } else {
                    step_result = self.executeStep(
                        step,
                        &world,
                        tag_strings,
                        &scenario_info,
                        scenario_alloc,
                    );

                    switch (step_result.status) {
                        .failed, .pending, .undefined => {
                            should_skip = true;
                            if (overall_status == .passed) {
                                overall_status = step_result.status;
                            }
                        },
                        .passed => {},
                        .skipped => {},
                    }
                }

                try step_results.append(step_result);
                self.notifyTestStepFinished(pickle, step_index, step_result);
            }

            scenario_info.status = overall_status;

            // 7. Run After hooks (always, even on failure).
            const after_hooks = self.hook_registry.getAfterHooks(tag_strings);
            for (after_hooks) |hook| {
                hook.func(@ptrCast(&world), scenario_info) catch {
                    if (overall_status == .passed) {
                        overall_status = .failed;
                    }
                };
            }

            // 8. Cleanup World.
            if (@hasDecl(WorldType, "deinit")) {
                world.deinit();
            }

            // Compute duration.
            const duration_ns: u64 = if (case_timer) |*timer| timer.read() else 0;

            const owned_results = try step_results.toOwnedSlice();

            const result = types.TestCaseResult{
                .pickle = pickle,
                .step_results = owned_results,
                .status = overall_status,
                .duration_ns = duration_ns,
            };

            self.notifyTestCaseFinished(result);

            return result;
        }

        // ── Step execution ──────────────────────────────────────

        fn executeStep(
            self: *Self,
            step: types.PickleStep,
            world: *WorldType,
            tag_strings: []const []const u8,
            scenario_info: *types.ScenarioInfo,
            scenario_alloc: Allocator,
        ) types.StepResult {
            // 6a. Run BeforeStep hooks.
            const before_step_hooks = self.hook_registry.getBeforeStepHooks(tag_strings);
            for (before_step_hooks) |hook| {
                hook.func(@ptrCast(world), scenario_info.*) catch {
                    return .{
                        .status = .failed,
                        .duration_ns = 0,
                        .err_message = "BeforeStep hook failed",
                        .step_text = step.text,
                        .step_keyword = step.keyword,
                    };
                };
            }

            var step_timer = std.time.Timer.start() catch null;

            // 6b. Match step text against registry.
            const match_result = self.step_registry.findMatch(step.text, scenario_alloc) catch {
                return .{
                    .status = .failed,
                    .duration_ns = 0,
                    .err_message = "Error matching step",
                    .step_text = step.text,
                    .step_keyword = step.keyword,
                };
            };

            const step_result = if (match_result) |matched| blk: {
                // Free the match result args when done (they were allocated by the expression matcher).
                defer matched.match_result.deinit();

                // 6d. Convert PickleStepArgument to StepArg and append to matched args.
                var args = std.ArrayList(types.StepArg).init(scenario_alloc);
                args.appendSlice(matched.args) catch {
                    break :blk types.StepResult{
                        .status = .failed,
                        .duration_ns = 0,
                        .err_message = "Failed to build step args",
                        .step_text = step.text,
                        .step_keyword = step.keyword,
                    };
                };

                switch (step.argument) {
                    .table => |pickle_table| {
                        const dt = convertTable(pickle_table, scenario_alloc) catch {
                            break :blk types.StepResult{
                                .status = .failed,
                                .duration_ns = 0,
                                .err_message = "Failed to convert table argument",
                                .step_text = step.text,
                                .step_keyword = step.keyword,
                            };
                        };
                        args.append(.{ .table = dt }) catch {};
                    },
                    .doc_string => |pickle_ds| {
                        args.append(.{
                            .doc_string = .{
                                .content = pickle_ds.content,
                                .content_type = pickle_ds.media_type,
                            },
                        }) catch {};
                    },
                    .none => {},
                }

                // 6e. Call the step function.
                const step_args: types.StepArgs = args.items;
                if (matched.step_def.func(@ptrCast(world), step_args)) {
                    const duration = if (step_timer) |*timer| timer.read() else 0;
                    break :blk types.StepResult{
                        .status = .passed,
                        .duration_ns = duration,
                        .step_text = step.text,
                        .step_keyword = step.keyword,
                    };
                } else |err| {
                    const duration = if (step_timer) |*timer| timer.read() else 0;
                    // 6f. Check for Pending error.
                    if (err == error.Pending) {
                        break :blk types.StepResult{
                            .status = .pending,
                            .duration_ns = duration,
                            .err = err,
                            .err_message = "Step is pending",
                            .step_text = step.text,
                            .step_keyword = step.keyword,
                        };
                    }
                    break :blk types.StepResult{
                        .status = .failed,
                        .duration_ns = duration,
                        .err = err,
                        .step_text = step.text,
                        .step_keyword = step.keyword,
                    };
                }
            } else blk: {
                // 6c. No match: mark as undefined, collect snippet.
                const has_table = step.argument == .table;
                const has_doc_string = step.argument == .doc_string;
                const snippet = SnippetGenerator.generate(
                    step.text,
                    step.keyword,
                    has_table,
                    has_doc_string,
                    self.allocator,
                ) catch null;
                if (snippet) |s| {
                    self.snippet_buf.append(s) catch {};
                }
                break :blk types.StepResult{
                    .status = .undefined,
                    .duration_ns = 0,
                    .step_text = step.text,
                    .step_keyword = step.keyword,
                };
            };

            // 6g. Run AfterStep hooks (always, even on failure).
            // Update scenario status so hooks see the current step result.
            scenario_info.status = step_result.status;
            var after_step_failed = false;
            const after_step_hooks = self.hook_registry.getAfterStepHooks(tag_strings);
            for (after_step_hooks) |hook| {
                hook.func(@ptrCast(world), scenario_info.*) catch {
                    after_step_failed = true;
                };
            }

            // If the step itself passed but an AfterStep hook failed, mark as failed.
            if (after_step_failed and step_result.status == .passed) {
                return .{
                    .status = .failed,
                    .duration_ns = step_result.duration_ns,
                    .err_message = "AfterStep hook failed",
                    .step_text = step.text,
                    .step_keyword = step.keyword,
                };
            }

            return step_result;
        }

        // ── Helpers ─────────────────────────────────────────────

        fn extractTagStrings(self: *Self, pickle_tags: []const types.PickleTag, alloc: Allocator) ![]const []const u8 {
            _ = self;
            const result = try alloc.alloc([]const u8, pickle_tags.len);
            for (pickle_tags, 0..) |tag, i| {
                result[i] = tag.name;
            }
            return result;
        }

        /// Convert a PickleTable into a DataTable ([]const []const []const u8).
        fn convertTable(pickle_table: types.PickleTable, alloc: Allocator) !types.DataTable {
            const rows = try alloc.alloc([]const []const u8, pickle_table.rows.len);
            for (pickle_table.rows, 0..) |row, i| {
                const cells = try alloc.alloc([]const u8, row.cells.len);
                for (row.cells, 0..) |cell, j| {
                    cells[j] = cell.value;
                }
                rows[i] = cells;
            }
            return .{ .rows = rows };
        }
    };
}

