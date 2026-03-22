const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const TagExpression = @import("tag_expression.zig").TagExpression;

// ── Hook Types ──

pub const HookType = enum {
    before_all,
    before,
    before_step,
    after_step,
    after,
    after_all,
};

pub const HookFn = *const fn (world: *anyopaque, info: types.ScenarioInfo) anyerror!void;
pub const SuiteHookFn = *const fn () anyerror!void;

pub const Hook = struct {
    hook_type: HookType,
    tag_filter: ?TagExpression,
    func: HookFn,
    order: i32,
    name: []const u8,

    /// Returns true if this hook should run for a scenario with the given tags.
    pub fn matches(self: *const Hook, tags: []const []const u8) bool {
        if (self.tag_filter) |filter| {
            return filter.evaluate(tags);
        }
        return true;
    }
};

pub const SuiteHook = struct {
    hook_type: HookType,
    func: SuiteHookFn,
    order: i32,
    name: []const u8,
};

// ── Hook Registry ──

pub const HookRegistry = struct {
    allocator: Allocator,
    before_hooks: std.ArrayList(Hook),
    after_hooks: std.ArrayList(Hook),
    before_step_hooks: std.ArrayList(Hook),
    after_step_hooks: std.ArrayList(Hook),
    before_all_hooks: std.ArrayList(SuiteHook),
    after_all_hooks: std.ArrayList(SuiteHook),

    // Separate scratch buffers for each hook type so that concurrent
    // get*Hooks calls don't invalidate each other's returned slices.
    before_filtered_buf: std.ArrayList(Hook),
    after_filtered_buf: std.ArrayList(Hook),
    before_step_filtered_buf: std.ArrayList(Hook),
    after_step_filtered_buf: std.ArrayList(Hook),
    before_all_filtered_buf: std.ArrayList(SuiteHook),
    after_all_filtered_buf: std.ArrayList(SuiteHook),

    pub fn init(allocator: Allocator) HookRegistry {
        return .{
            .allocator = allocator,
            .before_hooks = std.ArrayList(Hook).init(allocator),
            .after_hooks = std.ArrayList(Hook).init(allocator),
            .before_step_hooks = std.ArrayList(Hook).init(allocator),
            .after_step_hooks = std.ArrayList(Hook).init(allocator),
            .before_all_hooks = std.ArrayList(SuiteHook).init(allocator),
            .after_all_hooks = std.ArrayList(SuiteHook).init(allocator),
            .before_filtered_buf = std.ArrayList(Hook).init(allocator),
            .after_filtered_buf = std.ArrayList(Hook).init(allocator),
            .before_step_filtered_buf = std.ArrayList(Hook).init(allocator),
            .after_step_filtered_buf = std.ArrayList(Hook).init(allocator),
            .before_all_filtered_buf = std.ArrayList(SuiteHook).init(allocator),
            .after_all_filtered_buf = std.ArrayList(SuiteHook).init(allocator),
        };
    }

    pub fn deinit(self: *HookRegistry) void {
        // Free any tag expressions we allocated.
        for (self.before_hooks.items) |*h| {
            if (h.tag_filter) |*tf| tf.deinit();
        }
        for (self.after_hooks.items) |*h| {
            if (h.tag_filter) |*tf| tf.deinit();
        }
        for (self.before_step_hooks.items) |*h| {
            if (h.tag_filter) |*tf| tf.deinit();
        }
        for (self.after_step_hooks.items) |*h| {
            if (h.tag_filter) |*tf| tf.deinit();
        }

        self.before_hooks.deinit();
        self.after_hooks.deinit();
        self.before_step_hooks.deinit();
        self.after_step_hooks.deinit();
        self.before_all_hooks.deinit();
        self.after_all_hooks.deinit();
        self.before_filtered_buf.deinit();
        self.after_filtered_buf.deinit();
        self.before_step_filtered_buf.deinit();
        self.after_step_filtered_buf.deinit();
        self.before_all_filtered_buf.deinit();
        self.after_all_filtered_buf.deinit();
    }

    // ── Registration ──

    pub fn addBefore(self: *HookRegistry, name: []const u8, tag_filter: ?[]const u8, order: i32, func: HookFn) !void {
        try self.before_hooks.append(.{
            .hook_type = .before,
            .tag_filter = try parseOptionalTagFilter(self.allocator, tag_filter),
            .func = func,
            .order = order,
            .name = name,
        });
    }

    pub fn addAfter(self: *HookRegistry, name: []const u8, tag_filter: ?[]const u8, order: i32, func: HookFn) !void {
        try self.after_hooks.append(.{
            .hook_type = .after,
            .tag_filter = try parseOptionalTagFilter(self.allocator, tag_filter),
            .func = func,
            .order = order,
            .name = name,
        });
    }

    pub fn addBeforeStep(self: *HookRegistry, name: []const u8, tag_filter: ?[]const u8, order: i32, func: HookFn) !void {
        try self.before_step_hooks.append(.{
            .hook_type = .before_step,
            .tag_filter = try parseOptionalTagFilter(self.allocator, tag_filter),
            .func = func,
            .order = order,
            .name = name,
        });
    }

    pub fn addAfterStep(self: *HookRegistry, name: []const u8, tag_filter: ?[]const u8, order: i32, func: HookFn) !void {
        try self.after_step_hooks.append(.{
            .hook_type = .after_step,
            .tag_filter = try parseOptionalTagFilter(self.allocator, tag_filter),
            .func = func,
            .order = order,
            .name = name,
        });
    }

    pub fn addBeforeAll(self: *HookRegistry, name: []const u8, order: i32, func: SuiteHookFn) !void {
        try self.before_all_hooks.append(.{
            .hook_type = .before_all,
            .func = func,
            .order = order,
            .name = name,
        });
    }

    pub fn addAfterAll(self: *HookRegistry, name: []const u8, order: i32, func: SuiteHookFn) !void {
        try self.after_all_hooks.append(.{
            .hook_type = .after_all,
            .func = func,
            .order = order,
            .name = name,
        });
    }

    // ── Retrieval ──

    /// Get Before hooks matching the given tags, sorted in ascending order.
    pub fn getBeforeHooks(self: *HookRegistry, tags: []const []const u8) []const Hook {
        return self.filterAndSort(&self.before_hooks, &self.before_filtered_buf, tags, .ascending);
    }

    /// Get After hooks matching the given tags, sorted in descending order.
    pub fn getAfterHooks(self: *HookRegistry, tags: []const []const u8) []const Hook {
        return self.filterAndSort(&self.after_hooks, &self.after_filtered_buf, tags, .descending);
    }

    /// Get BeforeStep hooks matching the given tags, sorted in ascending order.
    pub fn getBeforeStepHooks(self: *HookRegistry, tags: []const []const u8) []const Hook {
        return self.filterAndSort(&self.before_step_hooks, &self.before_step_filtered_buf, tags, .ascending);
    }

    /// Get AfterStep hooks matching the given tags, sorted in descending order.
    pub fn getAfterStepHooks(self: *HookRegistry, tags: []const []const u8) []const Hook {
        return self.filterAndSort(&self.after_step_hooks, &self.after_step_filtered_buf, tags, .descending);
    }

    /// Get BeforeAll hooks, sorted in ascending order.
    pub fn getBeforeAllHooks(self: *HookRegistry) []const SuiteHook {
        return self.sortSuiteHooks(&self.before_all_hooks, &self.before_all_filtered_buf, .ascending);
    }

    /// Get AfterAll hooks, sorted in descending order.
    pub fn getAfterAllHooks(self: *HookRegistry) []const SuiteHook {
        return self.sortSuiteHooks(&self.after_all_hooks, &self.after_all_filtered_buf, .descending);
    }

    // ── Internal helpers ──

    const SortDirection = enum { ascending, descending };

    fn filterAndSort(
        _: *HookRegistry,
        hooks: *const std.ArrayList(Hook),
        buf: *std.ArrayList(Hook),
        tags: []const []const u8,
        direction: SortDirection,
    ) []const Hook {
        buf.clearRetainingCapacity();
        for (hooks.items) |hook| {
            if (hook.matches(tags)) {
                buf.append(hook) catch return &.{};
            }
        }
        const items = buf.items;
        switch (direction) {
            .ascending => std.mem.sort(Hook, items, {}, orderAscending),
            .descending => std.mem.sort(Hook, items, {}, orderDescending),
        }
        return items;
    }

    fn sortSuiteHooks(
        _: *HookRegistry,
        hooks: *const std.ArrayList(SuiteHook),
        buf: *std.ArrayList(SuiteHook),
        direction: SortDirection,
    ) []const SuiteHook {
        buf.clearRetainingCapacity();
        for (hooks.items) |hook| {
            buf.append(hook) catch return &.{};
        }
        const items = buf.items;
        switch (direction) {
            .ascending => std.mem.sort(SuiteHook, items, {}, suiteOrderAscending),
            .descending => std.mem.sort(SuiteHook, items, {}, suiteOrderDescending),
        }
        return items;
    }

    fn orderAscending(_: void, a: Hook, b: Hook) bool {
        return a.order < b.order;
    }

    fn orderDescending(_: void, a: Hook, b: Hook) bool {
        return a.order > b.order;
    }

    fn suiteOrderAscending(_: void, a: SuiteHook, b: SuiteHook) bool {
        return a.order < b.order;
    }

    fn suiteOrderDescending(_: void, a: SuiteHook, b: SuiteHook) bool {
        return a.order > b.order;
    }
};

fn parseOptionalTagFilter(allocator: Allocator, expr: ?[]const u8) !?TagExpression {
    const raw = expr orelse return null;
    return try TagExpression.parse(raw, allocator);
}

