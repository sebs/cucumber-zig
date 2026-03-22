const std = @import("std");
const types = @import("../types.zig");
const Formatter = @import("../Formatter.zig");

const PrettyFormatter = @This();

writer: std.io.AnyWriter,
use_colors: bool,
current_uri: ?[]const u8 = null,

pub fn init(writer: std.io.AnyWriter) PrettyFormatter {
    return .{
        .writer = writer,
        .use_colors = detectColors(),
    };
}

pub fn formatter(self: *PrettyFormatter) Formatter {
    return Formatter.init(self);
}

// ── Formatter callbacks ──

pub fn onTestRunStarted(self: *PrettyFormatter) void {
    _ = self;
}

pub fn onTestCaseStarted(self: *PrettyFormatter, info: types.TestCaseInfo) void {
    const pickle = info.pickle;

    // Print feature header when URI changes
    const uri_changed = if (self.current_uri) |cur| !std.mem.eql(u8, cur, pickle.uri) else true;
    if (uri_changed) {
        self.current_uri = pickle.uri;
        if (self.use_colors) {
            self.writer.print("\n{s}Feature:{s} {s}\n", .{ "\x1b[1m", "\x1b[0m", pickle.uri }) catch {};
        } else {
            self.writer.print("\nFeature: {s}\n", .{pickle.uri}) catch {};
        }
    }

    // Print scenario name with tags
    if (pickle.tags.len > 0) {
        self.writer.writeAll("  ") catch {};
        for (pickle.tags) |tag| {
            if (self.use_colors) {
                self.writer.print("\x1b[36m{s}\x1b[0m ", .{tag.name}) catch {};
            } else {
                self.writer.print("{s} ", .{tag.name}) catch {};
            }
        }
        self.writer.writeAll("\n") catch {};
    }

    self.writer.print("  Scenario: {s}\n", .{pickle.name}) catch {};
}

pub fn onTestStepFinished(self: *PrettyFormatter, pickle: types.Pickle, step_index: usize, result: types.StepResult) void {
    _ = pickle;
    _ = step_index;

    const symbol = result.status.symbol();
    const keyword = result.step_keyword;
    const text = result.step_text;

    if (self.use_colors) {
        const clr = result.status.color();
        self.writer.print("    {s}{s} {s}{s}{s}\n", .{ clr, symbol, keyword, text, "\x1b[0m" }) catch {};
    } else {
        self.writer.print("    {s} {s}{s}\n", .{ symbol, keyword, text }) catch {};
    }

    // Print error message for failed steps
    if (result.status == .failed) {
        if (result.err_message) |msg| {
            if (self.use_colors) {
                self.writer.print("      \x1b[31m{s}\x1b[0m\n", .{msg}) catch {};
            } else {
                self.writer.print("      {s}\n", .{msg}) catch {};
            }
        } else if (result.err) |err| {
            if (self.use_colors) {
                self.writer.print("      \x1b[31mError: {s}\x1b[0m\n", .{@errorName(err)}) catch {};
            } else {
                self.writer.print("      Error: {s}\n", .{@errorName(err)}) catch {};
            }
        }
    }

    // Print hint for undefined steps
    if (result.status == .undefined) {
        if (self.use_colors) {
            self.writer.print("      \x1b[33mYou can implement this step\x1b[0m\n", .{}) catch {};
        } else {
            self.writer.print("      You can implement this step\n", .{}) catch {};
        }
    }
}

pub fn onTestRunFinished(self: *PrettyFormatter, summary: types.RunSummary) void {
    self.writer.writeAll("\n") catch {};

    const duration_ms = summary.duration_ns / 1_000_000;
    const duration_s = duration_ms / 1000;
    const remainder_ms = duration_ms % 1000;

    self.writer.print("{d} scenario(s)", .{summary.total}) catch {};
    if (summary.passed > 0) self.printCount("passed", summary.passed, .passed);
    if (summary.failed > 0) self.printCount("failed", summary.failed, .failed);
    if (summary.skipped > 0) self.printCount("skipped", summary.skipped, .skipped);
    if (summary.undefined > 0) self.printCount("undefined", summary.undefined, .undefined);
    if (summary.pending > 0) self.printCount("pending", summary.pending, .pending);
    self.writer.writeAll("\n") catch {};

    self.writer.print("{d}.{d:0>3}s\n", .{ duration_s, remainder_ms }) catch {};
}

fn printCount(self: *PrettyFormatter, label: []const u8, count: u32, status: types.StepStatus) void {
    if (self.use_colors) {
        self.writer.print(" ({s}{d} {s}\x1b[0m)", .{ status.color(), count, label }) catch {};
    } else {
        self.writer.print(" ({d} {s})", .{ count, label }) catch {};
    }
}

fn detectColors() bool {
    // Respect NO_COLOR convention (https://no-color.org)
    if (std.posix.getenv("NO_COLOR")) |_| return false;

    // Check if stdout is a TTY
    if (std.posix.getenv("TERM")) |term| {
        if (std.mem.eql(u8, term, "dumb")) return false;
    }

    return std.posix.isatty(std.posix.STDOUT_FILENO);
}