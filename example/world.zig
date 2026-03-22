const std = @import("std");

/// The World represents the state shared across steps within a single scenario.
/// Each scenario gets a fresh World instance.
pub const World = struct {
    accounts: std.StringHashMap(Account),
    last_error: ?TransactionError = null,
    allocator: std.mem.Allocator,

    pub const Account = struct {
        name: []const u8,
        balance: i64,
    };

    pub const TransactionError = enum {
        insufficient_funds,
    };

    pub fn init(allocator: std.mem.Allocator) !World {
        return .{
            .accounts = std.StringHashMap(Account).init(allocator),
            .last_error = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *World) void {
        self.accounts.deinit();
    }

    pub fn createAccount(self: *World, name: []const u8) !void {
        try self.accounts.put(name, .{ .name = name, .balance = 0 });
    }

    pub fn getAccount(self: *World, name: []const u8) ?*Account {
        return self.accounts.getPtr(name);
    }

    pub fn deposit(self: *World, name: []const u8, amount: i64) !void {
        const account = self.getAccount(name) orelse return error.AccountNotFound;
        account.balance += amount;
    }

    pub fn withdraw(self: *World, name: []const u8, amount: i64) !void {
        const account = self.getAccount(name) orelse return error.AccountNotFound;
        if (account.balance < amount) {
            self.last_error = .insufficient_funds;
            return error.InsufficientFunds;
        }
        account.balance -= amount;
        self.last_error = null;
    }

    pub fn transfer(self: *World, from: []const u8, to: []const u8, amount: i64) !void {
        const from_acct = self.getAccount(from) orelse return error.AccountNotFound;
        if (from_acct.balance < amount) {
            self.last_error = .insufficient_funds;
            return error.InsufficientFunds;
        }
        const to_acct = self.getAccount(to) orelse return error.AccountNotFound;
        from_acct.balance -= amount;
        to_acct.balance += amount;
        self.last_error = null;
    }
};
