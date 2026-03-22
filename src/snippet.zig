const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

// ── Detected parameter in step text ──

const ParamKind = enum {
    int,
    float,
    string,
};

const DetectedParam = struct {
    kind: ParamKind,
    start: usize,
    end: usize, // exclusive
    example: []const u8,
};

// ── Snippet Generator ──

pub const SnippetGenerator = struct {
    /// Generate a Zig step function stub for an undefined step.
    /// `step_text` is the step text from the feature file (e.g., "I have 42 cucumbers")
    /// `keyword` is the Gherkin keyword (e.g., "Given", "When", "Then")
    /// `has_table` indicates if the step has a DataTable argument
    /// `has_doc_string` indicates if the step has a DocString argument
    pub fn generate(
        step_text: []const u8,
        keyword: []const u8,
        has_table: bool,
        has_doc_string: bool,
        allocator: Allocator,
    ) ![]const u8 {
        // 1. Detect parameters in the step text.
        var params = std.ArrayList(DetectedParam).init(allocator);
        defer params.deinit();
        try detectParams(step_text, &params);

        // 2. Build the function name.
        const func_name = try buildFunctionName(step_text, keyword, params.items, allocator);
        defer allocator.free(func_name);

        // 3. Build the pattern (step text with placeholders).
        const pattern = try buildPattern(step_text, params.items, allocator);
        defer allocator.free(pattern);

        // 4. Render the full snippet.
        return renderSnippet(
            step_text,
            keyword,
            func_name,
            params.items,
            has_table,
            has_doc_string,
            allocator,
        );
    }
};

// ── Parameter detection ──

fn detectParams(text: []const u8, params: *std.ArrayList(DetectedParam)) !void {
    var i: usize = 0;
    while (i < text.len) {
        // Quoted strings: "..."
        if (text[i] == '"') {
            const start = i;
            i += 1;
            while (i < text.len and text[i] != '"') : (i += 1) {}
            if (i < text.len) {
                // text[i] == '"'
                i += 1;
                // Extract the content between quotes (without the quotes themselves).
                const example = text[start + 1 .. i - 1];
                try params.append(.{
                    .kind = .string,
                    .start = start,
                    .end = i,
                    .example = example,
                });
            }
            continue;
        }

        // Numbers: integers and floats.
        // A number must appear at a word boundary (start of text or preceded by whitespace).
        if (isDigitOrMinus(text[i]) and (i == 0 or text[i - 1] == ' ')) {
            const start = i;

            // Skip optional leading minus sign.
            if (text[i] == '-') {
                i += 1;
            }

            // Must have at least one digit after optional minus.
            if (i >= text.len or !isDigit(text[i])) {
                continue;
            }

            // Consume digits.
            while (i < text.len and isDigit(text[i])) : (i += 1) {}

            var is_float = false;
            // Check for decimal point followed by digits.
            if (i < text.len and text[i] == '.' and i + 1 < text.len and isDigit(text[i + 1])) {
                is_float = true;
                i += 1; // skip '.'
                while (i < text.len and isDigit(text[i])) : (i += 1) {}
            }

            // Ensure the number ends at a word boundary.
            if (i < text.len and text[i] != ' ' and text[i] != '"') {
                continue;
            }

            try params.append(.{
                .kind = if (is_float) .float else .int,
                .start = start,
                .end = i,
                .example = text[start..i],
            });
            continue;
        }

        i += 1;
    }
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isDigitOrMinus(c: u8) bool {
    return isDigit(c) or c == '-';
}

// ── Function name generation ──

fn buildFunctionName(
    text: []const u8,
    keyword: []const u8,
    params: []const DetectedParam,
    allocator: Allocator,
) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Append lowercased keyword.
    for (keyword) |c| {
        try result.append(toLower(c));
    }

    // Separator between keyword and step text.
    if (keyword.len > 0 and text.len > 0) {
        try result.append('_');
    }

    // Process the step text, replacing parameter spans with their placeholder names.
    var i: usize = 0;
    var param_idx: usize = 0;
    while (i < text.len) {
        // Check if we are at a parameter span.
        if (param_idx < params.len and i == params[param_idx].start) {
            if (result.items.len > 0 and result.items[result.items.len - 1] != '_') {
                try result.append('_');
            }
            const label = switch (params[param_idx].kind) {
                .int => "int",
                .float => "float",
                .string => "string",
            };
            try result.appendSlice(label);
            i = params[param_idx].end;
            param_idx += 1;
            continue;
        }

        const c = text[i];
        if (isAlpha(c)) {
            try result.append(toLower(c));
        } else if (isDigit(c)) {
            try result.append(c);
        } else if (c == ' ' or c == '-' or c == '_') {
            // Collapse multiple separators into a single underscore.
            if (result.items.len > 0 and result.items[result.items.len - 1] != '_') {
                try result.append('_');
            }
        }
        // Skip any other character.

        i += 1;
    }

    // Trim trailing underscore.
    while (result.items.len > 0 and result.items[result.items.len - 1] == '_') {
        _ = result.pop();
    }

    return result.toOwnedSlice();
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn toLower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

// ── Pattern generation (step text with placeholders) ──

fn buildPattern(
    text: []const u8,
    params: []const DetectedParam,
    allocator: Allocator,
) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    var param_idx: usize = 0;
    while (i < text.len) {
        if (param_idx < params.len and i == params[param_idx].start) {
            const placeholder = switch (params[param_idx].kind) {
                .int => "{int}",
                .float => "{float}",
                .string => "{string}",
            };
            try result.appendSlice(placeholder);
            i = params[param_idx].end;
            param_idx += 1;
            continue;
        }
        try result.append(text[i]);
        i += 1;
    }

    return result.toOwnedSlice();
}

// ── Snippet rendering ──

fn renderSnippet(
    step_text: []const u8,
    keyword: []const u8,
    func_name: []const u8,
    params: []const DetectedParam,
    has_table: bool,
    has_doc_string: bool,
    allocator: Allocator,
) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    const writer = out.writer();

    // Comment header.
    try writer.writeAll("// TODO: Implement this step\n");
    try writer.print("// {s} {s}\n", .{ keyword, step_text });

    // Function signature.
    try writer.print("fn {s}(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {{\n", .{func_name});

    // Suppress unused parameter warnings.
    try writer.writeAll("    _ = ctx;\n");
    try writer.writeAll("    _ = args;\n");

    // Arg comments for detected parameters.
    for (params, 0..) |p, idx| {
        const type_name = switch (p.kind) {
            .int => "i64",
            .float => "f64",
            .string => "[]const u8",
        };
        const field_name = switch (p.kind) {
            .int => "int",
            .float => "float",
            .string => "string",
        };
        try writer.print("    // args[{d}].{s} == {s} (e.g., {s})\n", .{
            idx,
            field_name,
            type_name,
            p.example,
        });
    }

    // Table argument comment.
    if (has_table) {
        try writer.print("    // args[{d}].table == DataTable\n", .{params.len});
    }

    // DocString argument comment.
    if (has_doc_string) {
        const doc_index = params.len + @as(usize, if (has_table) 1 else 0);
        try writer.print("    // args[{d}].doc_string == DocString\n", .{doc_index});
    }

    // Pending return.
    try writer.writeAll("    return error.Pending;\n");
    try writer.writeAll("}");

    return out.toOwnedSlice();
}

