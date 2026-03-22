const std = @import("std");
const Allocator = std.mem.Allocator;

// ── Tag Expression ──
//
// Boolean expressions over Cucumber tags, supporting:
//   - Tag literals: @smoke, @wip, @fast
//   - Logical operators: and, or, not
//   - Parenthesised grouping: (@smoke or @wip) and not @slow
//
// Operator precedence (highest to lowest): not > and > or
//
// Grammar (recursive descent):
//   expr     → and_expr ("or" and_expr)*
//   and_expr → not_expr ("and" not_expr)*
//   not_expr → "not" not_expr | primary
//   primary  → TAG | "(" expr ")"

pub const TagExpression = struct {
    root: *const Node,
    /// Tracks all heap-allocated nodes for cleanup.
    owned_nodes: std.ArrayList(*Node),
    allocator: Allocator,

    const Node = union(enum) {
        tag: []const u8,
        @"and": [2]*const Node,
        @"or": [2]*const Node,
        not: *const Node,
        true_lit,
    };

    const ParseError = error{
        UnexpectedToken,
        UnexpectedEnd,
        UnmatchedParen,
    };

    // ── Public API ─────────────────────────────────────────────

    /// Parse a tag expression string.
    pub fn parse(expression: []const u8, allocator: Allocator) !TagExpression {
        var owned = std.ArrayList(*Node).init(allocator);
        errdefer {
            for (owned.items) |ptr| allocator.destroy(ptr);
            owned.deinit();
        }

        const trimmed = std.mem.trim(u8, expression, " \t\r\n");
        if (trimmed.len == 0) {
            const node = try allocNode(allocator, &owned, .true_lit);
            return .{ .root = node, .owned_nodes = owned, .allocator = allocator };
        }

        var pos: usize = 0;
        const root = try parseOr(trimmed, &pos, allocator, &owned);
        skipWhitespace(trimmed, &pos);
        if (pos != trimmed.len) {
            return ParseError.UnexpectedToken;
        }
        return .{ .root = root, .owned_nodes = owned, .allocator = allocator };
    }

    /// Evaluate the expression against a set of tags.
    /// Returns true if the tags satisfy the expression.
    pub fn evaluate(self: *const TagExpression, tags: []const []const u8) bool {
        return evalNode(self.root, tags);
    }

    /// Free resources.
    pub fn deinit(self: *TagExpression) void {
        for (self.owned_nodes.items) |ptr| self.allocator.destroy(ptr);
        self.owned_nodes.deinit();
    }

    // ── Evaluation ─────────────────────────────────────────────

    fn evalNode(node: *const Node, tags: []const []const u8) bool {
        return switch (node.*) {
            .true_lit => true,
            .tag => |name| {
                for (tags) |t| {
                    if (std.mem.eql(u8, t, name)) return true;
                }
                return false;
            },
            .@"and" => |children| evalNode(children[0], tags) and evalNode(children[1], tags),
            .@"or" => |children| evalNode(children[0], tags) or evalNode(children[1], tags),
            .not => |child| !evalNode(child, tags),
        };
    }

    // ── Recursive Descent Parser ──────────────────────────────

    fn parseOr(
        input: []const u8,
        pos: *usize,
        allocator: Allocator,
        owned: *std.ArrayList(*Node),
    ) (ParseError || Allocator.Error)!*const Node {
        var left = try parseAnd(input, pos, allocator, owned);
        while (true) {
            skipWhitespace(input, pos);
            if (matchKeyword(input, pos, "or")) {
                const right = try parseAnd(input, pos, allocator, owned);
                left = try allocNode(allocator, owned, .{ .@"or" = .{ left, right } });
            } else break;
        }
        return left;
    }

    fn parseAnd(
        input: []const u8,
        pos: *usize,
        allocator: Allocator,
        owned: *std.ArrayList(*Node),
    ) (ParseError || Allocator.Error)!*const Node {
        var left = try parseNot(input, pos, allocator, owned);
        while (true) {
            skipWhitespace(input, pos);
            if (matchKeyword(input, pos, "and")) {
                const right = try parseNot(input, pos, allocator, owned);
                left = try allocNode(allocator, owned, .{ .@"and" = .{ left, right } });
            } else break;
        }
        return left;
    }

    fn parseNot(
        input: []const u8,
        pos: *usize,
        allocator: Allocator,
        owned: *std.ArrayList(*Node),
    ) (ParseError || Allocator.Error)!*const Node {
        skipWhitespace(input, pos);
        if (matchKeyword(input, pos, "not")) {
            const child = try parseNot(input, pos, allocator, owned);
            return allocNode(allocator, owned, .{ .not = child });
        }
        return parsePrimary(input, pos, allocator, owned);
    }

    fn parsePrimary(
        input: []const u8,
        pos: *usize,
        allocator: Allocator,
        owned: *std.ArrayList(*Node),
    ) (ParseError || Allocator.Error)!*const Node {
        skipWhitespace(input, pos);
        if (pos.* >= input.len) return ParseError.UnexpectedEnd;

        if (input[pos.*] == '(') {
            pos.* += 1;
            const inner = try parseOr(input, pos, allocator, owned);
            skipWhitespace(input, pos);
            if (pos.* >= input.len or input[pos.*] != ')') {
                return ParseError.UnmatchedParen;
            }
            pos.* += 1;
            return inner;
        }

        if (input[pos.*] == '@') {
            const start = pos.*;
            pos.* += 1;
            while (pos.* < input.len and !isDelimiter(input[pos.*])) {
                pos.* += 1;
            }
            const name = input[start..pos.*];
            return allocNode(allocator, owned, .{ .tag = name });
        }

        return ParseError.UnexpectedToken;
    }

    // ── Helpers ────────────────────────────────────────────────

    /// Allocate a single Node on the heap and track it for later cleanup.
    /// Returns a stable pointer that will not be invalidated by future allocations.
    fn allocNode(
        allocator: Allocator,
        owned: *std.ArrayList(*Node),
        node: Node,
    ) Allocator.Error!*const Node {
        const ptr = try allocator.create(Node);
        ptr.* = node;
        try owned.append(ptr);
        return ptr;
    }

    fn skipWhitespace(input: []const u8, pos: *usize) void {
        while (pos.* < input.len and (input[pos.*] == ' ' or input[pos.*] == '\t')) {
            pos.* += 1;
        }
    }

    fn isDelimiter(c: u8) bool {
        return c == ' ' or c == '\t' or c == '(' or c == ')';
    }

    /// Try to match a keyword (and/or/not) at the current position.
    /// Keywords must be followed by whitespace, '(' or end-of-input to avoid
    /// matching prefixes of tag names. Advances pos on success.
    fn matchKeyword(input: []const u8, pos: *usize, keyword: []const u8) bool {
        const start = pos.*;
        if (start + keyword.len > input.len) return false;
        if (!std.mem.eql(u8, input[start .. start + keyword.len], keyword)) return false;

        const end = start + keyword.len;
        if (end < input.len and !isDelimiter(input[end])) return false;

        pos.* = end;
        return true;
    }
};
