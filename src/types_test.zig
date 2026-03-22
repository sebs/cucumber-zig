const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const DataTable = types.DataTable;
const StepArg = types.StepArg;

// ── DataTable.toSlice ──

test "DataTable.toSlice converts rows to typed structs" {
    const User = struct {
        name: []const u8,
        age: i32,
    };

    const table = DataTable{
        .rows = &.{
            &.{ "name", "age" },
            &.{ "Alice", "30" },
            &.{ "Bob", "25" },
        },
    };

    const users = try table.toSlice(User, testing.allocator);
    defer testing.allocator.free(users);

    try testing.expectEqual(@as(usize, 2), users.len);

    try testing.expectEqualStrings("Alice", users[0].name);
    try testing.expectEqual(@as(i32, 30), users[0].age);

    try testing.expectEqualStrings("Bob", users[1].name);
    try testing.expectEqual(@as(i32, 25), users[1].age);
}

// ── DataTable.cell bounds checking ──

test "DataTable.cell returns null for out-of-bounds row" {
    const table = DataTable{
        .rows = &.{
            &.{ "a", "b" },
            &.{ "1", "2" },
        },
    };

    try testing.expect(table.cell(999, 0) == null);
}

test "DataTable.cell returns null for out-of-bounds column" {
    const table = DataTable{
        .rows = &.{
            &.{ "a", "b" },
        },
    };

    try testing.expect(table.cell(0, 999) == null);
}

test "DataTable.cell returns value for valid indices" {
    const table = DataTable{
        .rows = &.{
            &.{ "x", "y" },
            &.{ "1", "2" },
        },
    };

    try testing.expectEqualStrings("x", table.cell(0, 0).?);
    try testing.expectEqualStrings("2", table.cell(1, 1).?);
}

// ── StepArg accessors ──

test "StepArg.asInt returns value for int variant" {
    const arg = StepArg{ .int = 42 };
    try testing.expectEqual(@as(i64, 42), try arg.asInt());
}

test "StepArg.asInt returns TypeMismatch for non-int variant" {
    const arg = StepArg{ .string = "hello" };
    try testing.expectError(error.TypeMismatch, arg.asInt());
}

test "StepArg.asFloat returns value for float variant" {
    const arg = StepArg{ .float = 3.14 };
    try testing.expectEqual(@as(f64, 3.14), try arg.asFloat());
}

test "StepArg.asFloat returns TypeMismatch for non-float variant" {
    const arg = StepArg{ .int = 1 };
    try testing.expectError(error.TypeMismatch, arg.asFloat());
}

test "StepArg.asString returns value for string variant" {
    const arg = StepArg{ .string = "hello" };
    try testing.expectEqualStrings("hello", try arg.asString());
}

test "StepArg.asString returns TypeMismatch for non-string variant" {
    const arg = StepArg{ .float = 1.0 };
    try testing.expectError(error.TypeMismatch, arg.asString());
}

// ── DataTable basic accessors ──

test "DataTable.headerRow returns first row" {
    const table = DataTable{
        .rows = &.{
            &.{ "name", "age" },
            &.{ "Alice", "30" },
        },
    };

    const header = table.headerRow();
    try testing.expectEqual(@as(usize, 2), header.len);
    try testing.expectEqualStrings("name", header[0]);
    try testing.expectEqualStrings("age", header[1]);
}

test "DataTable.headerRow returns empty for empty table" {
    const table = DataTable{ .rows = &.{} };
    try testing.expectEqual(@as(usize, 0), table.headerRow().len);
}

test "DataTable.dataRows returns all rows except header" {
    const table = DataTable{
        .rows = &.{
            &.{ "name", "age" },
            &.{ "Alice", "30" },
            &.{ "Bob", "25" },
        },
    };

    const data = table.dataRows();
    try testing.expectEqual(@as(usize, 2), data.len);
    try testing.expectEqualStrings("Alice", data[0][0]);
    try testing.expectEqualStrings("Bob", data[1][0]);
}

test "DataTable.dataRows returns empty when only header exists" {
    const table = DataTable{
        .rows = &.{
            &.{ "name", "age" },
        },
    };

    try testing.expectEqual(@as(usize, 0), table.dataRows().len);
}

test "DataTable.colCount returns number of columns" {
    const table = DataTable{
        .rows = &.{
            &.{ "a", "b", "c" },
        },
    };

    try testing.expectEqual(@as(usize, 3), table.colCount());
}

test "DataTable.colCount returns 0 for empty table" {
    const table = DataTable{ .rows = &.{} };
    try testing.expectEqual(@as(usize, 0), table.colCount());
}

test "DataTable.rowCount returns total number of rows" {
    const table = DataTable{
        .rows = &.{
            &.{ "name", "age" },
            &.{ "Alice", "30" },
            &.{ "Bob", "25" },
        },
    };

    try testing.expectEqual(@as(usize, 3), table.rowCount());
}
