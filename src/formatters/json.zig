const std = @import("std");
const types = @import("../types.zig");
const Formatter = @import("../Formatter.zig");

const JsonFormatter = @This();

writer: std.io.AnyWriter,
allocator: std.mem.Allocator,
results: std.ArrayList(types.TestCaseResult),

pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter) JsonFormatter {
    return .{
        .writer = writer,
        .allocator = allocator,
        .results = std.ArrayList(types.TestCaseResult).init(allocator),
    };
}

pub fn deinit(self: *JsonFormatter) void {
    self.results.deinit();
}

pub fn formatter(self: *JsonFormatter) Formatter {
    return Formatter.init(self);
}

// ── Formatter callbacks ──

pub fn onTestCaseFinished(self: *JsonFormatter, result: types.TestCaseResult) void {
    self.results.append(result) catch {};
}

pub fn onTestRunFinished(self: *JsonFormatter, summary: types.RunSummary) void {
    _ = summary;
    self.writeJson() catch {};
}

fn writeJson(self: *JsonFormatter) !void {
    const w = self.writer;

    // Group results by URI to form feature objects
    var features = std.StringArrayHashMap(std.ArrayList(types.TestCaseResult)).init(self.allocator);
    defer {
        var it = features.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        features.deinit();
    }

    for (self.results.items) |result| {
        const gop = features.getOrPut(result.pickle.uri) catch continue;
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(types.TestCaseResult).init(self.allocator);
        }
        gop.value_ptr.append(result) catch {};
    }

    try w.writeAll("[");

    var feature_idx: usize = 0;
    var feature_iter = features.iterator();
    while (feature_iter.next()) |entry| {
        if (feature_idx > 0) try w.writeAll(",");

        const uri = entry.key_ptr.*;
        const scenarios = entry.value_ptr.items;

        try w.writeAll("{");
        try writeJsonString(w, "uri");
        try w.writeAll(":");
        try writeJsonString(w, uri);
        try w.writeAll(",");
        try writeJsonString(w, "elements");
        try w.writeAll(":[");

        for (scenarios, 0..) |tc, sc_idx| {
            if (sc_idx > 0) try w.writeAll(",");

            try w.writeAll("{");
            try writeJsonString(w, "name");
            try w.writeAll(":");
            try writeJsonString(w, tc.pickle.name);
            try w.writeAll(",");
            try writeJsonString(w, "id");
            try w.writeAll(":");
            try writeJsonString(w, tc.pickle.id);
            try w.writeAll(",");
            try writeJsonString(w, "line");
            try w.writeAll(":");
            try w.print("{d}", .{tc.pickle.line});
            try w.writeAll(",");
            try writeJsonString(w, "type");
            try w.writeAll(":");
            try writeJsonString(w, "scenario");

            // Tags
            try w.writeAll(",");
            try writeJsonString(w, "tags");
            try w.writeAll(":[");
            for (tc.pickle.tags, 0..) |tag, ti| {
                if (ti > 0) try w.writeAll(",");
                try w.writeAll("{");
                try writeJsonString(w, "name");
                try w.writeAll(":");
                try writeJsonString(w, tag.name);
                try w.writeAll("}");
            }
            try w.writeAll("]");

            // Steps
            try w.writeAll(",");
            try writeJsonString(w, "steps");
            try w.writeAll(":[");
            for (tc.step_results, 0..) |sr, si| {
                if (si > 0) try w.writeAll(",");

                try w.writeAll("{");
                try writeJsonString(w, "keyword");
                try w.writeAll(":");
                try writeJsonString(w, sr.step_keyword);
                try w.writeAll(",");
                try writeJsonString(w, "name");
                try w.writeAll(":");
                try writeJsonString(w, sr.step_text);
                try w.writeAll(",");
                try writeJsonString(w, "result");
                try w.writeAll(":{");
                try writeJsonString(w, "status");
                try w.writeAll(":");
                try writeJsonString(w, @tagName(sr.status));
                try w.writeAll(",");
                try writeJsonString(w, "duration");
                try w.writeAll(":");
                try w.print("{d}", .{sr.duration_ns});

                if (sr.err_message) |msg| {
                    try w.writeAll(",");
                    try writeJsonString(w, "error_message");
                    try w.writeAll(":");
                    try writeJsonString(w, msg);
                }

                try w.writeAll("}}");
            }
            try w.writeAll("]");

            try w.writeAll("}");
        }

        try w.writeAll("]}");
        feature_idx += 1;
    }

    try w.writeAll("]\n");
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