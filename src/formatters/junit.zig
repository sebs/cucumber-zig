const std = @import("std");
const types = @import("../types.zig");
const Formatter = @import("../Formatter.zig");

const JunitFormatter = @This();

writer: std.io.AnyWriter,
allocator: std.mem.Allocator,
results: std.ArrayList(types.TestCaseResult),

pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter) JunitFormatter {
    return .{
        .writer = writer,
        .allocator = allocator,
        .results = std.ArrayList(types.TestCaseResult).init(allocator),
    };
}

pub fn deinit(self: *JunitFormatter) void {
    self.results.deinit();
}

pub fn formatter(self: *JunitFormatter) Formatter {
    return Formatter.init(self);
}

// ── Formatter callbacks ──

pub fn onTestCaseFinished(self: *JunitFormatter, result: types.TestCaseResult) void {
    self.results.append(result) catch {};
}

pub fn onTestRunFinished(self: *JunitFormatter, summary: types.RunSummary) void {
    self.writeXml(summary) catch {};
}

fn writeXml(self: *JunitFormatter, summary: types.RunSummary) !void {
    const w = self.writer;

    try w.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");

    const duration_s = floatSeconds(summary.duration_ns);
    try w.print("<testsuites tests=\"{d}\" failures=\"{d}\" time=\"{d:.3}\">\n", .{
        summary.total,
        summary.failed,
        duration_s,
    });

    // Group results by URI (feature file)
    var suites = std.StringArrayHashMap(std.ArrayList(types.TestCaseResult)).init(self.allocator);
    defer {
        for (suites.values()) |*list| {
            list.deinit();
        }
        suites.deinit();
    }

    for (self.results.items) |result| {
        const gop = suites.getOrPut(result.pickle.uri) catch continue;
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(types.TestCaseResult).init(self.allocator);
        }
        gop.value_ptr.append(result) catch {};
    }

    var suite_iter = suites.iterator();
    while (suite_iter.next()) |entry| {
        const uri = entry.key_ptr.*;
        const cases = entry.value_ptr.items;

        var suite_failures: u32 = 0;
        var suite_duration_ns: u64 = 0;
        for (cases) |c| {
            if (c.status == .failed) suite_failures += 1;
            suite_duration_ns += c.duration_ns;
        }

        try w.writeAll("  <testsuite name=\"");
        try writeXmlEscaped(w, uri);
        try w.print("\" tests=\"{d}\" failures=\"{d}\" time=\"{d:.3}\">\n", .{
            cases.len,
            suite_failures,
            floatSeconds(suite_duration_ns),
        });

        for (cases) |tc| {
            try w.writeAll("    <testcase name=\"");
            try writeXmlEscaped(w, tc.pickle.name);
            try w.writeAll("\" classname=\"");
            try writeXmlEscaped(w, tc.pickle.uri);
            try w.print("\" time=\"{d:.3}\"", .{
                floatSeconds(tc.duration_ns),
            });

            if (tc.status == .failed) {
                try w.writeAll(">\n");
                // Find first failed step for the message
                var failure_msg: []const u8 = "Scenario failed";
                for (tc.step_results) |sr| {
                    if (sr.status == .failed) {
                        if (sr.err_message) |msg| {
                            failure_msg = msg;
                        }
                        break;
                    }
                }
                try w.writeAll("      <failure message=\"");
                try writeXmlEscaped(w, failure_msg);
                try w.writeAll("\">");
                try writeXmlEscaped(w, failure_msg);
                try w.writeAll("</failure>\n");
                try w.writeAll("    </testcase>\n");
            } else if (tc.status == .skipped) {
                try w.writeAll(">\n");
                try w.writeAll("      <skipped/>\n");
                try w.writeAll("    </testcase>\n");
            } else {
                try w.writeAll("/>\n");
            }
        }

        try w.writeAll("  </testsuite>\n");
    }

    try w.writeAll("</testsuites>\n");
}

fn floatSeconds(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
}

/// Write XML-escaped text directly to the writer, handling all special characters.
fn writeXmlEscaped(w: std.io.AnyWriter, input: []const u8) !void {
    for (input) |c| {
        switch (c) {
            '<' => try w.writeAll("&lt;"),
            '>' => try w.writeAll("&gt;"),
            '&' => try w.writeAll("&amp;"),
            '"' => try w.writeAll("&quot;"),
            '\'' => try w.writeAll("&apos;"),
            else => try w.writeByte(c),
        }
    }
}