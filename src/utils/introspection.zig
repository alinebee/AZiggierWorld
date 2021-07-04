//! Tools to make type introspection less painful and wordy.

const std = @import("std");

/// A version of @intToEnum that returns error.IntToEnumError on failure.
pub const intToEnum = std.meta.intToEnum;

/// Given an integer type, returns the number of bits in that integer.
pub const bitCount = std.meta.bitCount;

/// Casts an integer type to another, returning an error on overflow (instead of trapping like @intCast).
pub const intCast = std.math.cast;

/// Given an integer type, returns the type used for legal left/right-shift operations.
pub const ShiftType = std.math.Log2Int;

/// Given a function reference, introspects the return type of that function.
pub fn ReturnType(comptime function: anytype) type {
    const type_info = @typeInfo(@TypeOf(function));
    return switch (type_info) {
        .Fn => |info| info.return_type.?,
        .BoundFn => |info| info.return_type.?,
        else => @compileError("Parameter was not a function or bound function"),
    };
}

/// Given a function that returns a regular type, an optional (`?payload`)
/// or an error union (`error_set!payload`), returns the type of the payload.
pub fn PayloadType(comptime function: anytype) type {
    const return_type = ReturnType(function);
    return switch (@typeInfo(return_type)) {
        .ErrorUnion => |info| info.payload,
        .Optional => |info| info.child,
        else => return_type,
    };
}

/// Given a function that returns an error union (`error_set!payload`),
/// returns the type of the error set.
/// Returns a compile error if the function does not return an error union.
pub fn ErrorType(comptime function: anytype) type {
    const return_type = ReturnType(function);
    return switch (@typeInfo(return_type)) {
        .ErrorUnion => |info| info.error_set,
        else => @compileError("Parameter did not return an ErrorUnion"),
    };
}

// -- Tests --

const testing = @import("testing.zig");

test "bitCount returns number of bits in integer" {
    try testing.expectEqual(0, bitCount(u0));
    try testing.expectEqual(1, bitCount(u1));
    try testing.expectEqual(4, bitCount(u4));
    try testing.expectEqual(8, bitCount(u8));
    try testing.expectEqual(16, bitCount(u16));
    try testing.expectEqual(32, bitCount(u32));
    try testing.expectEqual(64, bitCount(u64));
}

test "bitCount triggers compile error when passed non-integer" {
    // Uncomment me to trigger a compile error!
    //_ = bitCount(struct {});
}

test "ReturnType gets return type of free function" {
    const Namespace = struct {
        fn example() void {}
    };

    try testing.expectEqual(void, ReturnType(Namespace.example));
}

test "ReturnType gets return type of bound function" {
    const Struct = struct {
        const Self = @This();

        fn boundExample(self: Self) void {}
    };

    const foo = Struct{};
    try testing.expectEqual(void, ReturnType(foo.boundExample));
}

test "ReturnType triggers compile error when passed non-function type" {
    // Uncomment me to trigger a compile error!
    // _ = ReturnType(u32);
}

test "PayloadType gets return type of function that returns a type directly" {
    const Namespace = struct {
        fn example() u32 {
            return 0;
        }
    };

    try testing.expectEqual(u32, PayloadType(Namespace.example));
}

test "PayloadType gets return type of function that returns an optional" {
    const Namespace = struct {
        fn example() ?u32 {
            return null;
        }
    };

    try testing.expectEqual(u32, PayloadType(Namespace.example));
}

test "PayloadType gets return type of function that returns an error union" {
    const Namespace = struct {
        fn example() anyerror!u32 {
            return 0;
        }
    };

    try testing.expectEqual(u32, PayloadType(Namespace.example));
}

test "ErrorType gets return type of function that returns an error union" {
    const CustomError = error{FlagrantViolation};
    const Namespace = struct {
        fn example() CustomError!u32 {
            return 255;
        }
    };

    try testing.expectEqual(CustomError, ErrorType(Namespace.example));
}

test "ErrorType returns compile error when given function that does not return an error union" {
    const Namespace = struct {
        fn example() void {}
    };

    // Uncomment to trigger a compile-time error!
    //_ = ErrorType(Namespace.example);
}
