const std = @import("std");
const Allocator = std.mem.Allocator;

// ── Step Keywords ──

pub const Keyword = enum {
    given,
    when,
    then,
    any,

    pub fn toString(self: Keyword) []const u8 {
        return switch (self) {
            .given => "Given",
            .when => "When",
            .then => "Then",
            .any => "*",
        };
    }
};

// ── Source Location ──

pub const SourceLocation = struct {
    file: []const u8,
    line: u32,
};

// ── Step Arguments ──

pub const StepArg = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    table: DataTable,
    doc_string: DocString,

    pub fn asInt(self: StepArg) !i64 {
        return switch (self) {
            .int => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn asFloat(self: StepArg) !f64 {
        return switch (self) {
            .float => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn asString(self: StepArg) ![]const u8 {
        return switch (self) {
            .string => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn asTable(self: StepArg) !DataTable {
        return switch (self) {
            .table => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn asDocString(self: StepArg) !DocString {
        return switch (self) {
            .doc_string => |v| v,
            else => error.TypeMismatch,
        };
    }
};

pub const StepArgs = []const StepArg;

// ── Data Table ──

pub const DataTable = struct {
    rows: []const []const []const u8,

    pub fn headerRow(self: DataTable) []const []const u8 {
        if (self.rows.len == 0) return &.{};
        return self.rows[0];
    }

    pub fn dataRows(self: DataTable) []const []const []const u8 {
        if (self.rows.len <= 1) return &.{};
        return self.rows[1..];
    }

    pub fn cell(self: DataTable, row: usize, col: usize) ?[]const u8 {
        if (row >= self.rows.len) return null;
        if (col >= self.rows[row].len) return null;
        return self.rows[row][col];
    }

    pub fn rowCount(self: DataTable) usize {
        return self.rows.len;
    }

    pub fn colCount(self: DataTable) usize {
        if (self.rows.len == 0) return 0;
        return self.rows[0].len;
    }

    /// Convert each data row to a struct T using the header row for field names.
    pub fn toSlice(self: DataTable, comptime T: type, allocator: Allocator) ![]T {
        const header = self.headerRow();
        const data = self.dataRows();
        const result = try allocator.alloc(T, data.len);
        errdefer allocator.free(result);

        for (data, 0..) |row, i| {
            var item: T = std.mem.zeroes(T);
            inline for (std.meta.fields(T)) |field| {
                for (header, 0..) |col_name, col_idx| {
                    if (std.mem.eql(u8, col_name, field.name)) {
                        if (col_idx < row.len) {
                            @field(item, field.name) = coerceField(field.type, row[col_idx]) catch {
                                return error.CoercionFailed;
                            };
                        }
                        break;
                    }
                }
            }
            result[i] = item;
        }
        return result;
    }
};

fn coerceField(comptime T: type, value: []const u8) !T {
    if (T == []const u8) return value;
    if (T == i32) return std.fmt.parseInt(i32, value, 10);
    if (T == i64) return std.fmt.parseInt(i64, value, 10);
    if (T == u32) return std.fmt.parseInt(u32, value, 10);
    if (T == u64) return std.fmt.parseInt(u64, value, 10);
    if (T == f32) return std.fmt.parseFloat(f32, value);
    if (T == f64) return std.fmt.parseFloat(f64, value);
    if (T == bool) {
        if (std.mem.eql(u8, value, "true")) return true;
        if (std.mem.eql(u8, value, "false")) return false;
        return error.InvalidBool;
    }
    return error.UnsupportedType;
}

// ── Doc String ──

pub const DocString = struct {
    content_type: ?[]const u8,
    content: []const u8,
};

// ── Step Status ──

pub const StepStatus = enum {
    passed,
    failed,
    pending,
    skipped,
    undefined,

    pub fn symbol(self: StepStatus) []const u8 {
        return switch (self) {
            .passed => "✓",
            .failed => "✗",
            .skipped => "-",
            .undefined => "?",
            .pending => "P",
        };
    }

    pub fn color(self: StepStatus) []const u8 {
        return switch (self) {
            .passed => "\x1b[32m",
            .failed => "\x1b[31m",
            .skipped => "\x1b[36m",
            .undefined => "\x1b[33m",
            .pending => "\x1b[33m",
        };
    }
};

// ── Step Result ──

pub const StepResult = struct {
    status: StepStatus,
    duration_ns: u64 = 0,
    err: ?anyerror = null,
    err_message: ?[]const u8 = null,
    step_text: []const u8 = "",
    step_keyword: []const u8 = "",
};

// ── Scenario Info ──

pub const ScenarioInfo = struct {
    name: []const u8,
    tags: []const []const u8,
    uri: []const u8,
    line: u32,
    status: ?StepStatus,
};

// ── Pickle types (input from gherkin parser) ──

pub const PickleTag = struct {
    name: []const u8,
};

pub const PickleTable = struct {
    rows: []const PickleTableRow,
};

pub const PickleTableRow = struct {
    cells: []const PickleTableCell,
};

pub const PickleTableCell = struct {
    value: []const u8,
};

pub const PickleDocString = struct {
    content: []const u8,
    media_type: ?[]const u8,
};

pub const PickleStepArgument = union(enum) {
    table: PickleTable,
    doc_string: PickleDocString,
    none,
};

pub const PickleStep = struct {
    text: []const u8,
    keyword: []const u8,
    argument: PickleStepArgument = .none,
    id: []const u8 = "",
};

pub const Pickle = struct {
    id: []const u8,
    name: []const u8,
    uri: []const u8,
    line: u32 = 0,
    steps: []const PickleStep,
    tags: []const PickleTag,
};

// ── Test Case Results ──

pub const TestCaseInfo = struct {
    pickle: Pickle,
    attempt: u32 = 0,
};

pub const TestCaseResult = struct {
    pickle: Pickle,
    step_results: []const StepResult,
    status: StepStatus,
    duration_ns: u64,
};

pub const RunSummary = struct {
    total: u32 = 0,
    passed: u32 = 0,
    failed: u32 = 0,
    skipped: u32 = 0,
    undefined: u32 = 0,
    pending: u32 = 0,
    duration_ns: u64 = 0,
};

// ── Errors ──

pub const CucumberError = error{
    Pending,
    AmbiguousStep,
    UndefinedStep,
    TypeMismatch,
    CoercionFailed,
    InvalidExpression,
    InvalidRegex,
    InvalidTagExpression,
};
