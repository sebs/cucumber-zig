const std = @import("std");
const Allocator = std.mem.Allocator;

/// A minimal NFA-based regex engine using a Pike VM (Thompson NFA simulation
/// with capture-group tracking). Designed for patterns produced by Cucumber
/// Expressions.
pub const Regex = struct {
    instructions: []const Instruction,
    num_capture_groups: usize,
    allocator: Allocator,

    // -----------------------------------------------------------------------
    // Instruction set
    // -----------------------------------------------------------------------

    const CharClass = enum {
        digit, // \d
        space, // \s
        word, // \w
        not_digit, // \D
        not_space, // \S
        not_word, // \W
    };

    const CharRange = struct {
        lo: u8,
        hi: u8,
    };

    const Instruction = union(enum) {
        /// Match a literal byte.
        literal: u8,
        /// Match any byte except '\n'.
        any,
        /// Match a predefined character class.
        class: CharClass,
        /// Match a custom character set (bracket expression).
        bracket: struct {
            ranges: []const CharRange,
            negated: bool,
        },
        /// Unconditional jump.
        jmp: usize,
        /// Fork: try `primary` first, if that fails try `secondary`.
        split: struct {
            primary: usize,
            secondary: usize,
        },
        /// Save the current input position into capture slot `slot`.
        save: usize,
        /// Successful match.
        match_inst,
        /// Assert beginning of input.
        anchor_start,
        /// Assert end of input.
        anchor_end,
    };

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    /// Compile a regex pattern string.
    pub fn compile(pattern: []const u8, allocator: Allocator) !Regex {
        var compiler = Compiler.init(allocator);
        errdefer compiler.deinit();
        try compiler.compile(pattern);
        const instructions = try allocator.dupe(Instruction, compiler.instructions.items);
        // Compiler's ArrayList backing can be freed, but NOT the bracket ranges
        // since they're shared with the duped instructions. Only free the list itself.
        compiler.instructions.deinit();
        return Regex{
            .instructions = instructions,
            .num_capture_groups = compiler.num_capture_groups,
            .allocator = allocator,
        };
    }

    /// Match the regex against an input string. Returns captures if matched.
    /// captures[0] is the full match, captures[1..] are capture groups.
    pub fn match(self: *const Regex, input: []const u8, allocator: Allocator) !?[]const ?[]const u8 {
        return PikeVM.execute(self, input, allocator);
    }

    /// Check if the regex matches the input (no capture extraction).
    pub fn isMatch(self: *const Regex, input: []const u8) bool {
        const result = PikeVM.execute(self, input, self.allocator) catch return false;
        if (result) |captures| {
            self.allocator.free(captures);
            return true;
        }
        return false;
    }

    /// Free resources.
    pub fn deinit(self: *Regex, allocator: Allocator) void {
        for (self.instructions) |inst| {
            switch (inst) {
                .bracket => |b| allocator.free(b.ranges),
                else => {},
            }
        }
        allocator.free(self.instructions);
        self.instructions = &.{};
    }

    // -----------------------------------------------------------------------
    // Compiler  (pattern string -> instruction list)
    // -----------------------------------------------------------------------

    const Compiler = struct {
        instructions: std.ArrayList(Instruction),
        num_capture_groups: usize,
        alloc: Allocator,

        fn init(allocator: Allocator) Compiler {
            return .{
                .instructions = std.ArrayList(Instruction).init(allocator),
                .num_capture_groups = 0,
                .alloc = allocator,
            };
        }

        fn deinit(self: *Compiler) void {
            for (self.instructions.items) |inst| {
                switch (inst) {
                    .bracket => |b| self.alloc.free(b.ranges),
                    else => {},
                }
            }
            self.instructions.deinit();
        }

        fn emit(self: *Compiler, inst: Instruction) !usize {
            const pos = self.instructions.items.len;
            try self.instructions.append(inst);
            return pos;
        }

        fn pc(self: *const Compiler) usize {
            return self.instructions.items.len;
        }

        fn compile(self: *Compiler, pattern: []const u8) !void {
            _ = try self.emit(.{ .save = 0 });
            try self.compileAlternation(pattern, 0, pattern.len);
            _ = try self.emit(.{ .save = 1 });
            _ = try self.emit(.match_inst);
        }

        // -- recursive-descent parser ------------------------------------

        const CompileError = error{ OutOfMemory, TrailingBackslash, UnmatchedParen, UnmatchedBracket };
        fn compileAlternation(self: *Compiler, pat: []const u8, start: usize, end: usize) CompileError!void {
            var pipes = std.ArrayList(usize).init(self.alloc);
            defer pipes.deinit();

            var depth: usize = 0;
            var bracket = false;
            var i: usize = start;
            while (i < end) {
                const c = pat[i];
                if (bracket) {
                    if (c == '\\' and i + 1 < end) {
                        i += 2;
                        continue;
                    }
                    if (c == ']') bracket = false;
                    i += 1;
                    continue;
                }
                if (c == '[') {
                    bracket = true;
                    i += 1;
                    continue;
                }
                if (c == '\\' and i + 1 < end) {
                    i += 2;
                    continue;
                }
                if (c == '(') {
                    depth += 1;
                } else if (c == ')') {
                    depth -|= 1;
                } else if (c == '|' and depth == 0) {
                    try pipes.append(i);
                }
                i += 1;
            }

            if (pipes.items.len == 0) {
                try self.compileSequence(pat, start, end);
                return;
            }

            // Collect segment boundaries.
            const n_alts = pipes.items.len + 1;
            var seg_starts = std.ArrayList(usize).init(self.alloc);
            defer seg_starts.deinit();
            var seg_ends = std.ArrayList(usize).init(self.alloc);
            defer seg_ends.deinit();

            var seg_begin = start;
            for (pipes.items) |pipe_pos| {
                try seg_starts.append(seg_begin);
                try seg_ends.append(pipe_pos);
                seg_begin = pipe_pos + 1;
            }
            try seg_starts.append(seg_begin);
            try seg_ends.append(end);

            // For N alternatives we need N-1 splits.
            // Layout:
            //   split(alt0_body, next_split)
            //   alt0_body... jmp(done)
            //   split(alt1_body, next_split)   [or last: just alt body]
            //   alt1_body... jmp(done)
            //   ...
            //   altN_body...
            //   done:

            var split_pcs = std.ArrayList(usize).init(self.alloc);
            defer split_pcs.deinit();
            var jmp_pcs = std.ArrayList(usize).init(self.alloc);
            defer jmp_pcs.deinit();

            for (0..n_alts) |alt_idx| {
                if (alt_idx < n_alts - 1) {
                    const spc = try self.emit(.{ .split = .{ .primary = 0, .secondary = 0 } });
                    try split_pcs.append(spc);
                }
                try self.compileSequence(pat, seg_starts.items[alt_idx], seg_ends.items[alt_idx]);
                if (alt_idx < n_alts - 1) {
                    const jpc = try self.emit(.{ .jmp = 0 });
                    try jmp_pcs.append(jpc);
                }
            }

            const done = self.pc();

            // Patch splits: primary = instruction after the split (the body),
            //                secondary = the next split (or last body).
            for (split_pcs.items, 0..) |spc, idx| {
                const body_start = spc + 1;
                const next_alt: usize = if (idx + 1 < split_pcs.items.len)
                    split_pcs.items[idx + 1]
                else
                    jmp_pcs.items[jmp_pcs.items.len - 1] + 1; // start of last alt body
                self.instructions.items[spc] = .{ .split = .{
                    .primary = body_start,
                    .secondary = next_alt,
                } };
            }

            // Patch jumps to done.
            for (jmp_pcs.items) |jpc| {
                self.instructions.items[jpc] = .{ .jmp = done };
            }
        }

        fn compileSequence(self: *Compiler, pat: []const u8, start: usize, end: usize) CompileError!void {
            var i = start;
            while (i < end) {
                i = try self.compileAtom(pat, i, end);
            }
        }

        fn compileAtom(self: *Compiler, pat: []const u8, start: usize, end: usize) CompileError!usize {
            var i = start;
            const atom_start_pc = self.pc();

            const c = pat[i];
            var consumed: usize = 0;
            switch (c) {
                '^' => {
                    _ = try self.emit(.anchor_start);
                    return i + 1;
                },
                '$' => {
                    _ = try self.emit(.anchor_end);
                    return i + 1;
                },
                '.' => {
                    _ = try self.emit(.any);
                    consumed = 1;
                },
                '(' => {
                    const close = try findClosingParen(pat, i, end);
                    if (i + 2 < end and pat[i + 1] == '?' and pat[i + 2] == ':') {
                        try self.compileAlternation(pat, i + 3, close);
                    } else {
                        self.num_capture_groups += 1;
                        const group_idx = self.num_capture_groups;
                        _ = try self.emit(.{ .save = group_idx * 2 });
                        try self.compileAlternation(pat, i + 1, close);
                        _ = try self.emit(.{ .save = group_idx * 2 + 1 });
                    }
                    consumed = close - i + 1;
                },
                '[' => {
                    const bracket_end = try findClosingBracket(pat, i, end);
                    try self.compileBracket(pat, i, bracket_end);
                    consumed = bracket_end - i + 1;
                },
                '\\' => {
                    if (i + 1 >= end) return error.TrailingBackslash;
                    const next_ch = pat[i + 1];
                    switch (next_ch) {
                        'd' => _ = try self.emit(.{ .class = .digit }),
                        'D' => _ = try self.emit(.{ .class = .not_digit }),
                        's' => _ = try self.emit(.{ .class = .space }),
                        'S' => _ = try self.emit(.{ .class = .not_space }),
                        'w' => _ = try self.emit(.{ .class = .word }),
                        'W' => _ = try self.emit(.{ .class = .not_word }),
                        else => _ = try self.emit(.{ .literal = next_ch }),
                    }
                    consumed = 2;
                },
                else => {
                    _ = try self.emit(.{ .literal = c });
                    consumed = 1;
                },
            }

            i += consumed;

            // Check for quantifier.
            if (i < end) {
                switch (pat[i]) {
                    '*' => {
                        try self.wrapStar(atom_start_pc);
                        return i + 1;
                    },
                    '+' => {
                        try self.wrapPlus(atom_start_pc);
                        return i + 1;
                    },
                    '?' => {
                        try self.wrapQuestion(atom_start_pc);
                        return i + 1;
                    },
                    else => {},
                }
            }
            return i;
        }

        fn compileBracket(self: *Compiler, pat: []const u8, open: usize, close: usize) !void {
            var ranges = std.ArrayList(CharRange).init(self.alloc);
            defer ranges.deinit();

            var negated = false;
            var i = open + 1;
            if (i < close and pat[i] == '^') {
                negated = true;
                i += 1;
            }
            if (i < close and pat[i] == ']') {
                try ranges.append(.{ .lo = ']', .hi = ']' });
                i += 1;
            }
            while (i < close) {
                var ch = pat[i];
                if (ch == '\\' and i + 1 < close) {
                    ch = escInBracket(pat[i + 1]);
                    i += 2;
                } else {
                    i += 1;
                }
                if (i < close and pat[i] == '-' and i + 1 < close and pat[i + 1] != ']') {
                    i += 1;
                    var hi = pat[i];
                    if (hi == '\\' and i + 1 < close) {
                        hi = escInBracket(pat[i + 1]);
                        i += 2;
                    } else {
                        i += 1;
                    }
                    try ranges.append(.{ .lo = ch, .hi = hi });
                } else {
                    try ranges.append(.{ .lo = ch, .hi = ch });
                }
            }

            const owned = try self.alloc.dupe(CharRange, ranges.items);
            _ = try self.emit(.{ .bracket = .{ .ranges = owned, .negated = negated } });
        }

        fn escInBracket(ch: u8) u8 {
            return switch (ch) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                else => ch,
            };
        }

        // -- quantifier helpers ------------------------------------------

        fn extractBody(self: *Compiler, atom_start: usize) ![]Instruction {
            const body = try self.alloc.dupe(Instruction, self.instructions.items[atom_start..]);
            self.instructions.shrinkRetainingCapacity(atom_start);
            return body;
        }

        fn wrapStar(self: *Compiler, atom_start: usize) !void {
            // e* => L: split(body, done); body; jmp L; done:
            const body = try self.extractBody(atom_start);
            defer self.alloc.free(body);

            const split_pc = try self.emit(.{ .split = .{ .primary = 0, .secondary = 0 } });
            const body_start = self.pc();
            for (body) |inst| _ = try self.emit(inst);
            _ = try self.emit(.{ .jmp = split_pc });
            const done = self.pc();
            self.instructions.items[split_pc] = .{ .split = .{
                .primary = body_start,
                .secondary = done,
            } };
        }

        fn wrapPlus(self: *Compiler, atom_start: usize) !void {
            // e+ => body; split(body_start, done)
            const done = self.pc();
            _ = try self.emit(.{ .split = .{
                .primary = atom_start,
                .secondary = done + 1,
            } });
        }

        fn wrapQuestion(self: *Compiler, atom_start: usize) !void {
            // e? => split(body, done); body; done:
            const body = try self.extractBody(atom_start);
            defer self.alloc.free(body);

            const split_pc = try self.emit(.{ .split = .{ .primary = 0, .secondary = 0 } });
            const body_start = self.pc();
            for (body) |inst| _ = try self.emit(inst);
            const done = self.pc();
            self.instructions.items[split_pc] = .{ .split = .{
                .primary = body_start,
                .secondary = done,
            } };
        }

        // -- helpers -----------------------------------------------------

        fn findClosingParen(pat: []const u8, open: usize, end: usize) !usize {
            var depth: usize = 1;
            var i = open + 1;
            while (i < end) {
                if (pat[i] == '\\' and i + 1 < end) {
                    i += 2;
                    continue;
                }
                if (pat[i] == '(') depth += 1;
                if (pat[i] == ')') {
                    depth -= 1;
                    if (depth == 0) return i;
                }
                i += 1;
            }
            return error.UnmatchedParen;
        }

        fn findClosingBracket(pat: []const u8, open: usize, end: usize) !usize {
            var i = open + 1;
            if (i < end and pat[i] == '^') i += 1;
            if (i < end and pat[i] == ']') i += 1;
            while (i < end) {
                if (pat[i] == '\\' and i + 1 < end) {
                    i += 2;
                    continue;
                }
                if (pat[i] == ']') return i;
                i += 1;
            }
            return error.UnmatchedBracket;
        }
    };

    // -----------------------------------------------------------------------
    // Pike VM  (Thompson NFA simulation with capture tracking)
    // -----------------------------------------------------------------------

    const PikeVM = struct {
        fn execute(regex: *const Regex, input: []const u8, allocator: Allocator) !?[]const ?[]const u8 {
            const num_slots: usize = (regex.num_capture_groups + 1) * 2;
            const n_inst = regex.instructions.len;

            // We use two thread lists and swap them each step.
            var clist = std.ArrayList(Thread).init(allocator);
            defer {
                for (clist.items) |t| allocator.free(t.slots);
                clist.deinit();
            }
            var nlist = std.ArrayList(Thread).init(allocator);
            defer {
                for (nlist.items) |t| allocator.free(t.slots);
                nlist.deinit();
            }

            // Bitmap to prevent duplicate PCs in a thread list.
            const in_list = try allocator.alloc(u32, n_inst + 1);
            defer allocator.free(in_list);
            @memset(in_list, 0);
            var generation: u32 = 0;

            var best_slots: ?[]?usize = null;
            errdefer if (best_slots) |bs| allocator.free(bs);

            // Try starting match at each position.
            var sp: usize = 0;
            outer: while (sp <= input.len) : (sp += 1) {
                // Add initial thread.
                generation +%= 1;
                if (generation == 0) {
                    @memset(in_list, 0);
                    generation = 1;
                }

                const init_slots = try allocator.alloc(?usize, num_slots);
                @memset(init_slots, null);
                try addThread(&clist, regex, .{ .pc = 0, .slots = init_slots }, sp, input, in_list, generation, allocator, num_slots);

                var pos = sp;
                while (clist.items.len > 0) {
                    // Advance generation for next step.
                    generation +%= 1;
                    if (generation == 0) {
                        @memset(in_list, 0);
                        generation = 1;
                    }

                    // Free old nlist threads.
                    for (nlist.items) |t| allocator.free(t.slots);
                    nlist.clearRetainingCapacity();

                    for (clist.items) |t| {
                        if (t.pc >= n_inst) {
                            allocator.free(t.slots);
                            continue;
                        }
                        const inst = regex.instructions[t.pc];
                        const matched = switch (inst) {
                            .match_inst => {
                                if (best_slots == null) {
                                    best_slots = try allocator.dupe(?usize, t.slots);
                                } else {
                                    const cs = t.slots[0] orelse 0;
                                    const ce = t.slots[1] orelse 0;
                                    const bs = best_slots.?[0] orelse 0;
                                    const be = best_slots.?[1] orelse 0;
                                    if (cs < bs or (cs == bs and ce > be)) {
                                        for (best_slots.?, 0..) |_, si| {
                                            best_slots.?[si] = t.slots[si];
                                        }
                                    }
                                }
                                allocator.free(t.slots);
                                continue;
                            },
                            .literal => |ch| pos < input.len and input[pos] == ch,
                            .any => pos < input.len and input[pos] != '\n',
                            .class => |cls| pos < input.len and matchCharClass(cls, input[pos]),
                            .bracket => |b| pos < input.len and matchBracket(b.ranges, b.negated, input[pos]),
                            // Epsilon instructions were already expanded by addThread.
                            .jmp, .split, .save, .anchor_start, .anchor_end => {
                                allocator.free(t.slots);
                                continue;
                            },
                        };

                        if (matched) {
                            const new_slots = try allocator.dupe(?usize, t.slots);
                            try addThread(&nlist, regex, .{ .pc = t.pc + 1, .slots = new_slots }, pos + 1, input, in_list, generation, allocator, num_slots);
                        }
                        allocator.free(t.slots);
                    }
                    // All clist slots have been freed above; clear the item list
                    // so the swap doesn't leave stale entries that get double-freed.
                    clist.clearRetainingCapacity();

                    // Swap lists.
                    const tmp_items = clist.items;
                    const tmp_cap = clist.capacity;
                    clist.items = nlist.items;
                    clist.capacity = nlist.capacity;
                    nlist.items = tmp_items;
                    nlist.capacity = tmp_cap;

                    pos += 1;
                }

                if (best_slots != null) break :outer;
            }

            if (best_slots) |bs| {
                defer allocator.free(bs);
                const num_groups = regex.num_capture_groups + 1;
                const captures = try allocator.alloc(?[]const u8, num_groups);
                for (0..num_groups) |g| {
                    const s = bs[g * 2];
                    const e = bs[g * 2 + 1];
                    if (s != null and e != null) {
                        captures[g] = input[s.?..e.?];
                    } else {
                        captures[g] = null;
                    }
                }
                return captures;
            }
            return null;
        }

        const Thread = struct {
            pc: usize,
            slots: []?usize,
        };

        /// Recursively add a thread, following epsilon transitions (split, jmp,
        /// save, anchors). The `in_list` / `generation` bitmap prevents adding
        /// the same PC twice in one step, preserving priority (the first thread
        /// to reach a PC wins).
        fn addThread(
            list: *std.ArrayList(Thread),
            regex: *const Regex,
            thread: Thread,
            pos: usize,
            input: []const u8,
            in_list: []u32,
            generation: u32,
            allocator: Allocator,
            num_slots: usize,
        ) !void {
            _ = num_slots;
            const tpc = thread.pc;
            if (tpc >= regex.instructions.len) {
                // Let match_inst be handled by the main loop if it's at this PC.
                // Actually, if pc == instructions.len that's past the end, just
                // add it and let the main loop skip it.
                try list.append(thread);
                return;
            }

            if (in_list[tpc] == generation) {
                // Already have a thread at this PC with higher priority.
                allocator.free(thread.slots);
                return;
            }
            in_list[tpc] = generation;

            const inst = regex.instructions[tpc];
            switch (inst) {
                .jmp => |target| {
                    var t = thread;
                    t.pc = target;
                    try addThread(list, regex, t, pos, input, in_list, generation, allocator, 0);
                },
                .split => |s| {
                    // Primary first (higher priority).
                    const dup = try allocator.dupe(?usize, thread.slots);
                    errdefer allocator.free(dup);
                    try addThread(list, regex, .{ .pc = s.primary, .slots = thread.slots }, pos, input, in_list, generation, allocator, 0);
                    try addThread(list, regex, .{ .pc = s.secondary, .slots = dup }, pos, input, in_list, generation, allocator, 0);
                },
                .save => |slot| {
                    var t = thread;
                    if (slot < t.slots.len) {
                        t.slots[slot] = pos;
                    }
                    t.pc += 1;
                    try addThread(list, regex, t, pos, input, in_list, generation, allocator, 0);
                },
                .anchor_start => {
                    if (pos == 0) {
                        var t = thread;
                        t.pc += 1;
                        try addThread(list, regex, t, pos, input, in_list, generation, allocator, 0);
                    } else {
                        allocator.free(thread.slots);
                    }
                },
                .anchor_end => {
                    if (pos == input.len) {
                        var t = thread;
                        t.pc += 1;
                        try addThread(list, regex, t, pos, input, in_list, generation, allocator, 0);
                    } else {
                        allocator.free(thread.slots);
                    }
                },
                else => {
                    // Consuming instruction -- just add the thread.
                    try list.append(thread);
                },
            }
        }

        fn matchCharClass(cls: CharClass, ch: u8) bool {
            return switch (cls) {
                .digit => ch >= '0' and ch <= '9',
                .not_digit => !(ch >= '0' and ch <= '9'),
                .space => ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == 0x0C or ch == 0x0B,
                .not_space => !(ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == 0x0C or ch == 0x0B),
                .word => (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9') or ch == '_',
                .not_word => !((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9') or ch == '_'),
            };
        }

        fn matchBracket(ranges: []const CharRange, negated: bool, ch: u8) bool {
            for (ranges) |r| {
                if (ch >= r.lo and ch <= r.hi) return !negated;
            }
            return negated;
        }
    };
};
