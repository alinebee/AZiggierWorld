const intToEnum = @import("../utils/introspection.zig").intToEnum;

/// A raw ControlThreads operation as it is represented in bytecode.
pub const Raw = u8;

/// The possible operations for a ControlThreads instruction.
pub const Enum = enum(Raw) {
    /// Resume a previously paused thread.
    Resume = 0,
    /// Mark the threads as paused, but maintain their current state.
    Suspend = 1,
    /// Mark the threads as deactivated.
    Deactivate = 2,
};

pub const Error = error{
    /// The bytecode specified an unknown thread operation.
    InvalidThreadOperation,
};

/// Parse a valid operation type from a raw bytecode value.
/// Returns error.InvalidThreadOperation if the value could not be parsed.
pub fn parse(raw: Raw) Error!Enum {
    return intToEnum(Enum, raw) catch error.InvalidThreadOperation;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse parses raw operation bytes correctly" {
    try testing.expectEqual(.Resume, parse(0));
    try testing.expectEqual(.Suspend, parse(1));
    try testing.expectEqual(.Deactivate, parse(2));
    try testing.expectError(
        error.InvalidThreadOperation,
        parse(3),
    );
}
