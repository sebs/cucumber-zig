const std = @import("std");
const types = @import("../types.zig");
const Formatter = @import("../Formatter.zig");

const ProgressFormatter = @This();

writer: std.io.AnyWriter,
use_colors: bool,
step_count: usize = 0,

pub fn init(writer: std.io.AnyWriter) ProgressFormatter {
    return .{
        .writer = writer,
        .use_colors = detectColors(),
    };
}

pub fn formatter(self: *ProgressFormatter) Formatter {
    return Formatter.init(self);
}

// ── Formatter callbacks ──

pub fn onTestStepFinished(self: *ProgressFormatter, pickle: types.Pickle, step_index: usize, result: types.StepResult) void {
    _ = pickle;
    _ = step_index;

    const char: []const u8 = switch (result.status) {
        .passed => ".",
        .failed => "F",
        .undefined => "U",
        .pending => "P",
        .skipped => "-",
    };

    if (self.use_colors) {
        self.writer.print("{s}{s}\x1b[0m", .{ result.status.color(), char }) catch {};
    } else {
        self.writer.writeAll(char) catch {};
    }

    self.step_count += 1;

    // Line break every 70 characters for readability
    if (self.step_count % 70 == 0) {
        self.writer.writeAll("\n") catch {};
    }
}

pub fn onTestRunFinished(self: *ProgressFormatter, summary: types.RunSummary) void {
    self.writer.writeAll("\n\n") catch {};

    const duration_ms = summary.duration_ns / 1_000_000;
    const duration_s = duration_ms / 1000;
    const remainder_ms = duration_ms % 1000;

    self.writer.print("{d} scenario(s)", .{summary.total}) catch {};

    var parts: [5][]const u8 = undefined;
    var part_counts: [5]u32 = undefined;
    var part_statuses: [5]types.StepStatus = undefined;
    var part_len: usize = 0;

    if (summary.passed > 0) {
        parts[part_len] = "passed";
        part_counts[part_len] = summary.passed;
        part_statuses[part_len] = .passed;
        part_len += 1;
    }
    if (summary.failed > 0) {
        parts[part_len] = "failed";
        part_counts[part_len] = summary.failed;
        part_statuses[part_len] = .failed;
        part_len += 1;
    }
    if (summary.skipped > 0) {
        parts[part_len] = "skipped";
        part_counts[part_len] = summary.skipped;
        part_statuses[part_len] = .skipped;
        part_len += 1;
    }
    if (summary.undefined > 0) {
        parts[part_len] = "undefined";
        part_counts[part_len] = summary.undefined;
        part_statuses[part_len] = .undefined;
        part_len += 1;
    }
    if (summary.pending > 0) {
        parts[part_len] = "pending";
        part_counts[part_len] = summary.pending;
        part_statuses[part_len] = .pending;
        part_len += 1;
    }

    if (part_len > 0) {
        self.writer.writeAll(" (") catch {};
        for (0..part_len) |i| {
            if (i > 0) self.writer.writeAll(", ") catch {};
            if (self.use_colors) {
                self.writer.print("{s}{d} {s}\x1b[0m", .{ part_statuses[i].color(), part_counts[i], parts[i] }) catch {};
            } else {
                self.writer.print("{d} {s}", .{ part_counts[i], parts[i] }) catch {};
            }
        }
        self.writer.writeAll(")") catch {};
    }

    self.writer.writeAll("\n") catch {};
    self.writer.print("{d}.{d:0>3}s\n", .{ duration_s, remainder_ms }) catch {};
}

fn detectColors() bool {
    if (std.posix.getenv("NO_COLOR")) |_| return false;
    if (std.posix.getenv("TERM")) |term| {
        if (std.mem.eql(u8, term, "dumb")) return false;
    }
    return std.posix.isatty(std.posix.STDOUT_FILENO);
}