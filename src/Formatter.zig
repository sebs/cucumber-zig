const std = @import("std");
const types = @import("types.zig");

const Formatter = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    on_test_run_started: ?*const fn (ptr: *anyopaque) void = null,
    on_test_case_started: ?*const fn (ptr: *anyopaque, info: types.TestCaseInfo) void = null,
    on_test_step_started: ?*const fn (ptr: *anyopaque, pickle: types.Pickle, step_index: usize) void = null,
    on_test_step_finished: ?*const fn (ptr: *anyopaque, pickle: types.Pickle, step_index: usize, result: types.StepResult) void = null,
    on_test_case_finished: ?*const fn (ptr: *anyopaque, result: types.TestCaseResult) void = null,
    on_test_run_finished: ?*const fn (ptr: *anyopaque, summary: types.RunSummary) void = null,
};

pub fn onTestRunStarted(self: Formatter) void {
    if (self.vtable.on_test_run_started) |f| f(self.ptr);
}

pub fn onTestCaseStarted(self: Formatter, info: types.TestCaseInfo) void {
    if (self.vtable.on_test_case_started) |f| f(self.ptr, info);
}

pub fn onTestStepStarted(self: Formatter, pickle: types.Pickle, step_index: usize) void {
    if (self.vtable.on_test_step_started) |f| f(self.ptr, pickle, step_index);
}

pub fn onTestStepFinished(self: Formatter, pickle: types.Pickle, step_index: usize, result: types.StepResult) void {
    if (self.vtable.on_test_step_finished) |f| f(self.ptr, pickle, step_index, result);
}

pub fn onTestCaseFinished(self: Formatter, result: types.TestCaseResult) void {
    if (self.vtable.on_test_case_finished) |f| f(self.ptr, result);
}

pub fn onTestRunFinished(self: Formatter, summary: types.RunSummary) void {
    if (self.vtable.on_test_run_finished) |f| f(self.ptr, summary);
}

/// Create a Formatter from any pointer type whose pointee implements the formatter callbacks.
/// The implementation type may provide any subset of:
///   onTestRunStarted, onTestCaseStarted, onTestStepStarted,
///   onTestStepFinished, onTestCaseFinished, onTestRunFinished
pub fn init(pointer: anytype) Formatter {
    const Ptr = @TypeOf(pointer);
    const ptr_info = @typeInfo(Ptr);
    comptime {
        if (ptr_info != .pointer or ptr_info.pointer.size != .one) {
            @compileError("Expected a single-item pointer, got " ++ @typeName(Ptr));
        }
    }
    const Impl = ptr_info.pointer.child;

    const gen = struct {
        fn onTestRunStartedFn(erased: *anyopaque) void {
            const self: *Impl = @ptrCast(@alignCast(erased));
            self.onTestRunStarted();
        }
        fn onTestCaseStartedFn(erased: *anyopaque, info: types.TestCaseInfo) void {
            const self: *Impl = @ptrCast(@alignCast(erased));
            self.onTestCaseStarted(info);
        }
        fn onTestStepStartedFn(erased: *anyopaque, pickle: types.Pickle, step_index: usize) void {
            const self: *Impl = @ptrCast(@alignCast(erased));
            self.onTestStepStarted(pickle, step_index);
        }
        fn onTestStepFinishedFn(erased: *anyopaque, pickle: types.Pickle, step_index: usize, result: types.StepResult) void {
            const self: *Impl = @ptrCast(@alignCast(erased));
            self.onTestStepFinished(pickle, step_index, result);
        }
        fn onTestCaseFinishedFn(erased: *anyopaque, result: types.TestCaseResult) void {
            const self: *Impl = @ptrCast(@alignCast(erased));
            self.onTestCaseFinished(result);
        }
        fn onTestRunFinishedFn(erased: *anyopaque, summary: types.RunSummary) void {
            const self: *Impl = @ptrCast(@alignCast(erased));
            self.onTestRunFinished(summary);
        }

        const vtable = VTable{
            .on_test_run_started = if (@hasDecl(Impl, "onTestRunStarted")) onTestRunStartedFn else null,
            .on_test_case_started = if (@hasDecl(Impl, "onTestCaseStarted")) onTestCaseStartedFn else null,
            .on_test_step_started = if (@hasDecl(Impl, "onTestStepStarted")) onTestStepStartedFn else null,
            .on_test_step_finished = if (@hasDecl(Impl, "onTestStepFinished")) onTestStepFinishedFn else null,
            .on_test_case_finished = if (@hasDecl(Impl, "onTestCaseFinished")) onTestCaseFinishedFn else null,
            .on_test_run_finished = if (@hasDecl(Impl, "onTestRunFinished")) onTestRunFinishedFn else null,
        };
    };

    return .{
        .ptr = pointer,
        .vtable = &gen.vtable,
    };
}

