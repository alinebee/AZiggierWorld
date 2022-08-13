const intToEnum = @import("../utils/introspection.zig").intToEnum;

/// A raw ControlThreads operation as it is represented in bytecode.
const _Raw = u8;

/// The possible operations for a ControlThreads instruction.
pub const ThreadOperation = enum(Raw) {
    /// Resume a previously paused thread.
    // `resume` is a reserved keyword in Zig.
    @"resume" = 0,
    /// Mark the threads as paused, but maintain their current state.
    pause = 1,
    /// Mark the threads as deactivated.
    deactivate = 2,

    /// Parse a valid operation type from a raw bytecode value.
    /// Returns error.InvalidThreadOperation if the value could not be parsed.
    pub fn parse(raw: Raw) Error!ThreadOperation {
        return intToEnum(ThreadOperation, raw) catch error.InvalidThreadOperation;
    }

    /// Convert an operation type into its raw bytecode representation.
    pub fn encode(operation: ThreadOperation) Raw {
        return @enumToInt(operation);
    }

    /// A raw ControlThreads operation as it is represented in bytecode.
    pub const Raw = _Raw;

    pub const Error = error{
        /// The bytecode specified an unknown thread operation.
        InvalidThreadOperation,
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse parses raw operation bytes correctly" {
    try testing.expectEqual(.@"resume", ThreadOperation.parse(0));
    try testing.expectEqual(.pause, ThreadOperation.parse(1));
    try testing.expectEqual(.deactivate, ThreadOperation.parse(2));
    try testing.expectError(
        error.InvalidThreadOperation,
        ThreadOperation.parse(3),
    );
}
