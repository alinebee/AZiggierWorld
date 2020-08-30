/// A raw ControlThreads operation as it is represented in bytecode.
pub const Raw = u8;

/// The possible operations for a ControlThreads instruction.
pub const Enum = enum {
    /// Resume a previously paused thread.
    Resume,
    /// Mark the threads as paused, but maintain their current state.
    Suspend,
    /// Mark the threads as deactivated.
    Deactivate,
};

pub const Error = error {
    /// The bytecode specified an unknown thread operation.
    InvalidThreadOperation,
};

pub fn parse(raw_operation: Raw) Error!Enum {
    // It would be nicer to use @intToEnum, but that has undefined behaviour when the value is out of range.
    return switch (raw_operation) {
        0 => .Resume,
        1 => .Suspend,
        2 => .Deactivate,
        else => error.InvalidThreadOperation,
    };
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "parse parses raw operation bytes correctly" {
    testing.expectEqual(.Resume, parse(0));
    testing.expectEqual(.Suspend, parse(1));
    testing.expectEqual(.Deactivate, parse(2));
    testing.expectError(
        error.InvalidThreadOperation,
        parse(3),
    );
}
