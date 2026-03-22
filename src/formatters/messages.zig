const std = @import("std");
const types = @import("../types.zig");
const Formatter = @import("../Formatter.zig");

const MessagesFormatter = @This();

writer: std.io.AnyWriter,

pub fn init(writer: std.io.AnyWriter) MessagesFormatter {
    return .{
        .writer = writer,
    };
}

pub fn formatter(self: *MessagesFormatter) Formatter {
    return Formatter.init(self);
}

// ── Formatter callbacks ──

pub fn onTestRunStarted(self: *MessagesFormatter) void {
    self.writeMessage("testRunStarted", .{
        .timestamp = timestamp(0),
    }) catch {};
}

pub fn onTestCaseStarted(self: *MessagesFormatter, info: types.TestCaseInfo) void {
    self.writeMessage("testCaseStarted", .{
        .pickleId = info.pickle.id,
        .name = info.pickle.name,
        .attempt = info.attempt,
    }) catch {};
}

pub fn onTestStepStarted(self: *MessagesFormatter, pickle: types.Pickle, step_index: usize) void {
    const step_id = if (step_index < pickle.steps.len) pickle.steps[step_index].id else "";
    self.writeMessage("testStepStarted", .{
        .pickleId = pickle.id,
        .index = step_index,
        .stepId = step_id,
    }) catch {};
}

pub fn onTestStepFinished(self: *MessagesFormatter, pickle: types.Pickle, step_index: usize, result: types.StepResult) void {
    const step_id = if (step_index < pickle.steps.len) pickle.steps[step_index].id else "";
    if (result.err_message) |msg| {
        self.writeMessage("testStepFinished", .{
            .pickleId = pickle.id,
            .index = step_index,
            .stepId = step_id,
            .status = @tagName(result.status),
            .duration = result.duration_ns,
            .errorMessage = msg,
        }) catch {};
    } else {
        self.writeMessage("testStepFinished", .{
            .pickleId = pickle.id,
            .index = step_index,
            .stepId = step_id,
            .status = @tagName(result.status),
            .duration = result.duration_ns,
        }) catch {};
    }
}

pub fn onTestCaseFinished(self: *MessagesFormatter, result: types.TestCaseResult) void {
    self.writeMessage("testCaseFinished", .{
        .pickleId = result.pickle.id,
        .status = @tagName(result.status),
        .duration = result.duration_ns,
    }) catch {};
}

pub fn onTestRunFinished(self: *MessagesFormatter, summary: types.RunSummary) void {
    self.writeMessage("testRunFinished", .{
        .success = summary.failed == 0,
        .total = summary.total,
        .passed = summary.passed,
        .failed = summary.failed,
        .skipped = summary.skipped,
        .undefined = summary.undefined,
        .pending = summary.pending,
        .duration = summary.duration_ns,
    }) catch {};
}

fn writeMessage(self: *MessagesFormatter, message_type: []const u8, data: anytype) !void {
    const w = self.writer;
    try w.writeAll("{");
    try writeJsonString(w, message_type);
    try w.writeAll(":{");

    const fields = std.meta.fields(@TypeOf(data));
    inline for (fields, 0..) |field, i| {
        if (i > 0) try w.writeAll(",");
        try writeJsonString(w, field.name);
        try w.writeAll(":");
        const value = @field(data, field.name);
        try writeJsonValue(w, value);
    }

    try w.writeAll("}}\n");
}

fn writeJsonValue(w: std.io.AnyWriter, value: anytype) !void {
    const T = @TypeOf(value);
    if (T == []const u8) {
        try writeJsonString(w, value);
    } else if (comptime isStringLike(T)) {
        // Handle [:0]const u8 from @tagName, *const [N:0]u8 from string literals
        const slice: []const u8 = if (@typeInfo(T).pointer.size == .slice)
            value
        else
            std.mem.span(value);
        try writeJsonString(w, slice);
    } else if (T == bool) {
        try w.writeAll(if (value) "true" else "false");
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        try w.print("{d}", .{value});
    } else if (@typeInfo(T) == .@"struct") {
        try w.writeAll("{");
        const fields = std.meta.fields(T);
        inline for (fields, 0..) |field, i| {
            if (i > 0) try w.writeAll(",");
            try writeJsonString(w, field.name);
            try w.writeAll(":");
            try writeJsonValue(w, @field(value, field.name));
        }
        try w.writeAll("}");
    } else {
        try w.print("{d}", .{value});
    }
}

fn isStringLike(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    // Sentinel-terminated slices ([:0]const u8 from @tagName)
    if (info.pointer.size == .slice and info.pointer.child == u8) return true;
    // Pointer to array (*const [N:0]u8 from string literals)
    if (info.pointer.size == .one) {
        const child = @typeInfo(info.pointer.child);
        if (child == .array and child.array.child == u8) return true;
    }
    return false;
}

fn writeJsonString(w: std.io.AnyWriter, s: []const u8) !void {
    try w.writeAll("\"");
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try w.print("\\u{x:0>4}", .{c});
                } else {
                    try w.writeByte(c);
                }
            },
        }
    }
    try w.writeAll("\"");
}

const Timestamp = struct {
    seconds: u64,
    nanos: u64,
};

fn timestamp(ns: u64) Timestamp {
    return .{
        .seconds = ns / 1_000_000_000,
        .nanos = ns % 1_000_000_000,
    };
}