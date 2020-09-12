const std = @import("std");

/// Prints a logging statement from a function that's not yet implemented,
/// describing what would have happened when the function was called.
pub fn log_unimplemented(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("\n[UNIMPLEMENTED] ", .{});
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}