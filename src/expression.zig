const std = @import("std");
const Allocator = std.mem.Allocator;
const Regex = @import("regex.zig").Regex;
const types = @import("types.zig");

// ── Cucumber Expression Compiler ──
//
// Compiles Cucumber Expressions (human-friendly step patterns) into regex
// patterns with typed capture groups. Also supports raw regex passthrough.
//
// Cucumber Expression syntax:
//   {int}        → captures an integer:   (-?\d+)
//   {float}      → captures a float:      (-?\d*\.\d+)
//   {word}       → captures a word:       ([^\s]+)
//   {string}     → captures a quoted str: ("([^"]*)")|('([^']*)')
//   {}           → captures anything:     (.*)
//   text(s)      → optional text:         (?:text(?:s)?)
//   a/b          → alternation:           (?:a|b)
//
// Heuristic: if a pattern starts with ^ or ends with $, it is treated as
// a raw regex. Otherwise it is compiled as a Cucumber Expression.

pub const ParamType = enum {
    int,
    float,
    word,
    string,
    anonymous,
    custom,
};

pub const CaptureDescriptor = struct {
    param_type: ParamType,
    group_index: u32,
};

pub const MatchResult = struct {
    args: []const types.StepArg,
    allocator: Allocator,

    pub fn deinit(self: MatchResult) void {
        self.allocator.free(self.args);
    }
};

pub const CompiledExpression = struct {
    regex: Regex,
    captures: []const CaptureDescriptor,
    original: []const u8,
    is_raw_regex: bool,
    allocator: Allocator,

    /// Try to match `text` against this expression.
    /// On success, returns a MatchResult with parsed arguments.
    /// Returns null if the text does not match.
    pub fn match(self: *const CompiledExpression, text: []const u8) !?MatchResult {
        const groups_opt = try self.regex.match(text, self.allocator);
        if (groups_opt == null) return null;
        const groups = groups_opt.?;
        defer self.allocator.free(groups);

        if (self.is_raw_regex) {
            // For raw regex, every capture group becomes a string arg.
            // groups[0] is the full match; groups[1..] are capture groups.
            var arg_list = std.ArrayList(types.StepArg).init(self.allocator);
            defer arg_list.deinit();
            for (groups[1..]) |g| {
                if (g) |val| {
                    try arg_list.append(.{ .string = val });
                }
            }
            const args = try arg_list.toOwnedSlice();
            return MatchResult{ .args = args, .allocator = self.allocator };
        }

        // For Cucumber Expressions, use capture descriptors to parse args.
        var args = try self.allocator.alloc(types.StepArg, self.captures.len);
        errdefer self.allocator.free(args);

        for (self.captures, 0..) |cap, i| {
            // For {string}, we emit two capture groups (double-quoted and
            // single-quoted). Only one of them will match. We need to find
            // which one is non-null.
            if (cap.param_type == .string) {
                // Try the primary group index first, then the next one.
                const raw = groups[cap.group_index] orelse groups[cap.group_index + 1] orelse return error.InvalidExpression;
                args[i] = .{ .string = raw };
            } else {
                const raw = groups[cap.group_index] orelse return error.InvalidExpression;
                args[i] = switch (cap.param_type) {
                    .int => .{ .int = std.fmt.parseInt(i64, raw, 10) catch return error.TypeMismatch },
                    .float => .{ .float = std.fmt.parseFloat(f64, raw) catch return error.TypeMismatch },
                    .word => .{ .string = raw },
                    .anonymous => .{ .string = raw },
                    .custom => .{ .string = raw },
                    .string => unreachable,
                };
            }
        }

        return MatchResult{ .args = args, .allocator = self.allocator };
    }

    pub fn deinit(self: *CompiledExpression) void {
        self.regex.deinit(self.allocator);
        self.allocator.free(self.captures);
    }
};

/// Compile a Cucumber Expression or raw regex pattern.
///
/// If `pattern` starts with '^' or ends with '$', it is treated as a raw
/// regex and compiled directly. Otherwise it is parsed as a Cucumber
/// Expression and translated to a regex pattern.
pub fn compile(pattern: []const u8, allocator: Allocator) !CompiledExpression {
    if (isRawRegex(pattern)) {
        return compileRawRegex(pattern, allocator);
    }
    return compileCucumberExpression(pattern, allocator);
}

// ── Heuristic: raw regex detection ────────────────────────────

pub fn isRawRegex(pattern: []const u8) bool {
    if (pattern.len == 0) return false;
    if (pattern[0] == '^') return true;
    if (pattern[pattern.len - 1] == '$') return true;
    return false;
}

fn compileRawRegex(pattern: []const u8, allocator: Allocator) !CompiledExpression {
    const regex = Regex.compile(pattern, allocator) catch return error.InvalidRegex;
    const captures = try allocator.alloc(CaptureDescriptor, 0);
    return CompiledExpression{
        .regex = regex,
        .captures = captures,
        .original = pattern,
        .is_raw_regex = true,
        .allocator = allocator,
    };
}

// ── Cucumber Expression compiler ──────────────────────────────

fn compileCucumberExpression(pattern: []const u8, allocator: Allocator) !CompiledExpression {
    var regex_buf = std.ArrayList(u8).init(allocator);
    defer regex_buf.deinit();
    var cap_list = std.ArrayList(CaptureDescriptor).init(allocator);
    defer cap_list.deinit();

    var group_index: u32 = 1;
    try regex_buf.append('^');

    // Process pattern word-by-word. Words are separated by spaces.
    // Within a word, unescaped '/' denotes alternation.
    var i: usize = 0;
    while (i < pattern.len) {
        if (pattern[i] == ' ') {
            try regex_buf.append(' ');
            i += 1;
            continue;
        }

        // Collect alternation alternatives for this word.
        var alt_starts = std.ArrayList(usize).init(allocator);
        defer alt_starts.deinit();
        var alt_ends = std.ArrayList(usize).init(allocator);
        defer alt_ends.deinit();

        var alt_start = i;
        var j = i;
        while (j < pattern.len and pattern[j] != ' ') {
            if (pattern[j] == '\\' and j + 1 < pattern.len) {
                j += 2; // skip escape sequence
            } else if (pattern[j] == '{') {
                j += 1;
                while (j < pattern.len and pattern[j] != '}') : (j += 1) {}
                if (j < pattern.len) j += 1;
            } else if (pattern[j] == '(') {
                j += 1;
                while (j < pattern.len and pattern[j] != ')') : (j += 1) {}
                if (j < pattern.len) j += 1;
            } else if (pattern[j] == '/') {
                try alt_starts.append(alt_start);
                try alt_ends.append(j);
                j += 1;
                alt_start = j;
            } else {
                j += 1;
            }
        }
        try alt_starts.append(alt_start);
        try alt_ends.append(j);

        if (alt_starts.items.len > 1) {
            try regex_buf.appendSlice("(?:");
            for (alt_starts.items, alt_ends.items, 0..) |s, e, idx| {
                if (idx > 0) try regex_buf.append('|');
                try compileFragment(pattern[s..e], &regex_buf, &cap_list, &group_index);
            }
            try regex_buf.append(')');
        } else {
            try compileFragment(
                pattern[alt_starts.items[0]..alt_ends.items[0]],
                &regex_buf,
                &cap_list,
                &group_index,
            );
        }

        i = j;
    }

    try regex_buf.append('$');

    const regex_pattern = try regex_buf.toOwnedSlice();
    defer allocator.free(regex_pattern);

    const regex = Regex.compile(regex_pattern, allocator) catch return error.InvalidRegex;
    const captures = try cap_list.toOwnedSlice();

    return CompiledExpression{
        .regex = regex,
        .captures = captures,
        .original = pattern,
        .is_raw_regex = false,
        .allocator = allocator,
    };
}

/// Compile a single fragment (no alternation) into the regex buffer.
/// Handles parameters {}, optionals (), and escape sequences \.
fn compileFragment(
    fragment: []const u8,
    regex_buf: *std.ArrayList(u8),
    cap_list: *std.ArrayList(CaptureDescriptor),
    group_index: *u32,
) !void {
    var i: usize = 0;
    while (i < fragment.len) {
        const c = fragment[i];
        switch (c) {
            '\\' => {
                if (i + 1 < fragment.len) {
                    const next = fragment[i + 1];
                    switch (next) {
                        '(', ')', '{', '}', '/', '\\' => {
                            try appendEscapedChar(regex_buf, next);
                            i += 2;
                        },
                        else => {
                            try appendEscapedChar(regex_buf, c);
                            i += 1;
                        },
                    }
                } else {
                    try appendEscapedChar(regex_buf, c);
                    i += 1;
                }
            },
            '{' => {
                const close = std.mem.indexOfScalarPos(u8, fragment, i + 1, '}') orelse
                    return error.InvalidExpression;
                const name = fragment[i + 1 .. close];
                try emitParam(name, regex_buf, cap_list, group_index);
                i = close + 1;
            },
            '(' => {
                const close = std.mem.indexOfScalarPos(u8, fragment, i + 1, ')') orelse
                    return error.InvalidExpression;
                const optional_text = fragment[i + 1 .. close];
                try regex_buf.appendSlice("(?:");
                try appendEscaped(regex_buf, optional_text);
                try regex_buf.appendSlice(")?");
                i = close + 1;
            },
            else => {
                try appendEscapedChar(regex_buf, c);
                i += 1;
            },
        }
    }
}

/// Emit the regex fragment and capture descriptor for a parameter placeholder.
fn emitParam(
    name: []const u8,
    buf: *std.ArrayList(u8),
    caps: *std.ArrayList(CaptureDescriptor),
    group_index: *u32,
) !void {
    if (name.len == 0) {
        // Anonymous: {}
        try buf.appendSlice("(.*)");
        try caps.append(.{ .param_type = .anonymous, .group_index = group_index.* });
        group_index.* += 1;
    } else if (std.mem.eql(u8, name, "int")) {
        try buf.appendSlice("(-?\\d+)");
        try caps.append(.{ .param_type = .int, .group_index = group_index.* });
        group_index.* += 1;
    } else if (std.mem.eql(u8, name, "float")) {
        try buf.appendSlice("(-?\\d*\\.?\\d+)");
        try caps.append(.{ .param_type = .float, .group_index = group_index.* });
        group_index.* += 1;
    } else if (std.mem.eql(u8, name, "word")) {
        try buf.appendSlice("([^\\s]+)");
        try caps.append(.{ .param_type = .word, .group_index = group_index.* });
        group_index.* += 1;
    } else if (std.mem.eql(u8, name, "string")) {
        // {string} matches either "..." or '...' and captures the inner text.
        // We use two capture groups, one per quote style. The CaptureDescriptor
        // records the first group index; match() checks both.
        try buf.appendSlice("(?:\"([^\"]*)\"|'([^']*)')");
        try caps.append(.{ .param_type = .string, .group_index = group_index.* });
        group_index.* += 2; // two capture groups
    } else {
        // Custom / unknown parameter type: treat as anonymous capture.
        try buf.appendSlice("(.*)");
        try caps.append(.{ .param_type = .custom, .group_index = group_index.* });
        group_index.* += 1;
    }
}

// ── Regex escaping ────────────────────────────────────────────

fn isRegexMeta(c: u8) bool {
    return switch (c) {
        '.', '*', '+', '?', '|', '[', ']', '(', ')', '{', '}', '^', '$', '\\' => true,
        else => false,
    };
}

fn appendEscapedChar(buf: *std.ArrayList(u8), c: u8) !void {
    if (isRegexMeta(c)) {
        try buf.append('\\');
    }
    try buf.append(c);
}

fn appendEscaped(buf: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |c| {
        try appendEscapedChar(buf, c);
    }
}

