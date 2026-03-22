const std = @import("std");
const cucumber = @import("cucumber");
const World = @import("../world.zig").World;

fn asWorld(ctx: *anyopaque) *World {
    return @ptrCast(@alignCast(ctx));
}

// ── Given ──

fn newAccount(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
    const world = asWorld(ctx);
    const name = try args[0].asString();
    try world.createAccount(name);
}

fn hasBalance(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
    const world = asWorld(ctx);
    const name = try args[0].asString();
    const amount = try args[1].asInt();
    try world.deposit(name, amount);
}

// ── When ──

fn depositMoney(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
    const world = asWorld(ctx);
    const amount = try args[0].asInt();
    // Use the first account (from Background)
    var it = world.accounts.iterator();
    if (it.next()) |entry| {
        try world.deposit(entry.key_ptr.*, amount);
    } else {
        return error.NoAccount;
    }
}

fn withdrawMoney(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
    const world = asWorld(ctx);
    const amount = try args[0].asInt();
    var it = world.accounts.iterator();
    if (it.next()) |entry| {
        try world.withdraw(entry.key_ptr.*, amount);
    } else {
        return error.NoAccount;
    }
}

fn tryWithdraw(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
    const world = asWorld(ctx);
    const amount = try args[0].asInt();
    var it = world.accounts.iterator();
    if (it.next()) |entry| {
        world.withdraw(entry.key_ptr.*, amount) catch |err| {
            if (err == error.InsufficientFunds) return; // expected failure
            return err;
        };
    } else {
        return error.NoAccount;
    }
}

fn transferMoney(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
    const world = asWorld(ctx);
    const from = try args[0].asString();
    const amount = try args[1].asInt();
    const to = try args[2].asString();
    try world.transfer(from, to, amount);
}

fn tryTransfer(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
    const world = asWorld(ctx);
    const from = try args[0].asString();
    const amount = try args[1].asInt();
    const to = try args[2].asString();
    world.transfer(from, to, amount) catch |err| {
        if (err == error.InsufficientFunds) return; // expected failure
        return err;
    };
}

// ── Then ──

fn checkBalance(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
    const world = asWorld(ctx);
    const expected = try args[0].asInt();
    var it = world.accounts.iterator();
    if (it.next()) |entry| {
        if (entry.value_ptr.balance != expected) {
            std.debug.print("Expected balance {d}, got {d}\n", .{ expected, entry.value_ptr.balance });
            return error.BalanceMismatch;
        }
    } else {
        return error.NoAccount;
    }
}

fn checkNamedBalance(ctx: *anyopaque, args: cucumber.StepArgs) anyerror!void {
    const world = asWorld(ctx);
    const name = try args[0].asString();
    const expected = try args[1].asInt();
    const account = world.getAccount(name) orelse return error.AccountNotFound;
    if (account.balance != expected) {
        std.debug.print("{s}: expected balance {d}, got {d}\n", .{ name, expected, account.balance });
        return error.BalanceMismatch;
    }
}

fn withdrawalDeclined(ctx: *anyopaque, _: cucumber.StepArgs) anyerror!void {
    const world = asWorld(ctx);
    if (world.last_error != .insufficient_funds) {
        return error.ExpectedDecline;
    }
}

fn transferDeclined(ctx: *anyopaque, _: cucumber.StepArgs) anyerror!void {
    const world = asWorld(ctx);
    if (world.last_error != .insufficient_funds) {
        return error.ExpectedDecline;
    }
}

// ── Registration ──

pub fn register(registry: *cucumber.StepRegistry) !void {
    // Given
    try registry.given("a new account for {string}", newAccount);
    try registry.given("{string} has a balance of {int}", hasBalance);

    // When
    try registry.when("I deposit {int}", depositMoney);
    try registry.when("I withdraw {int}", withdrawMoney);
    try registry.when("I try to withdraw {int}", tryWithdraw);
    try registry.when("{string} transfers {int} to {string}", transferMoney);
    try registry.when("{string} tries to transfer {int} to {string}", tryTransfer);

    // Then
    try registry.then("the balance should be {int}", checkBalance);
    try registry.then("{string} should have a balance of {int}", checkNamedBalance);
    try registry.then("the withdrawal should be declined", withdrawalDeclined);
    try registry.then("the transfer should be declined", transferDeclined);
}
