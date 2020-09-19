//! Tools to make type introspection less painful and wordy.

const std = @import("std");

/// A version of @intToEnum that returns error.IntToEnumError on failure.
pub const intToEnum = std.meta.intToEnum;

/// Given an integer type, returns the number of bits in that integer.
pub const bitCount = std.meta.bitCount;

/// Given an integer type, returns the type used for legal left/right-shift operations.
pub const shiftType = std.math.Log2Int;

/// Given a function reference, introspects the return type of that function.
pub fn returnType(comptime function: anytype) type {
    const type_info = @typeInfo(@TypeOf(function));
    return switch (type_info) {
        .Fn => |info| info.return_type.?,
        .BoundFn => |info| info.return_type.?,
        else => @compileError("Parameter was not a function or bound function"),
    };
}

/// Given a function that returns a regular type, an optional (`?payload`)
/// or an error union (`error_set!payload`), returns the type of the payload.
pub fn payloadType(comptime function: anytype) type {
    const return_type = returnType(function);
    return switch (@typeInfo(return_type)) {
        .ErrorUnion => |info| info.payload,
        .Optional => |info| info.child,
        else => return_type,
    };
}

/// Given a function that returns an error union (`error_set!payload`),
/// returns the type of the error set.
/// Returns a compile error if the function does not return an error union.
pub fn errorType(comptime function: anytype) type {
    const return_type = returnType(function);
    return switch (@typeInfo(return_type)) {
        .ErrorUnion => |info| info.error_set,
        else => @compileError("Parameter did not return an ErrorUnion"),
    };
}

// -- Tests --

const testing = @import("testing.zig");

test "bitCount returns number of bits in integer" {
    testing.expectEqual(0, bitCount(u0));
    testing.expectEqual(1, bitCount(u1));
    testing.expectEqual(4, bitCount(u4));
    testing.expectEqual(8, bitCount(u8));
    testing.expectEqual(16, bitCount(u16));
    testing.expectEqual(32, bitCount(u32));
    testing.expectEqual(64, bitCount(u64));
}

test "bitCount triggers compile error when passed non-integer" {
    // Uncomment me to trigger a compile error!
    //_ = bitCount(struct {});
}

test "returnType gets return type of free function" {
    const Namespace = struct {
        fn example() void {}
    };

    testing.expectEqual(void, returnType(Namespace.example));
}

test "returnType gets return type of bound function" {
    const Struct = struct {
        const Self = @This();

        fn boundExample(self: Self) void {}
    };

    const foo = Struct{};
    testing.expectEqual(void, returnType(foo.boundExample));
}

test "returnType triggers compile error when passed non-function type" {
    // Uncomment me to trigger a compile error!
    // _ = returnType(u32);
}

test "payloadType gets return type of function that returns a type directly" {
    const Namespace = struct {
        fn example() u32 {
            return 0;
        }
    };

    testing.expectEqual(u32, payloadType(Namespace.example));
}

test "payloadType gets return type of function that returns an optional" {
    const Namespace = struct {
        fn example() ?u32 {
            return null;
        }
    };

    testing.expectEqual(u32, payloadType(Namespace.example));
}

test "payloadType gets return type of function that returns an error union" {
    const Namespace = struct {
        fn example() anyerror!u32 {
            return 0;
        }
    };

    testing.expectEqual(u32, payloadType(Namespace.example));
}

test "errorType gets return type of function that returns an error union" {
    const CustomError = error{FlagrantViolation};
    const Namespace = struct {
        fn example() CustomError!u32 {
            return 255;
        }
    };

    testing.expectEqual(CustomError, errorType(Namespace.example));
}

test "errorType returns compile error when given function that does not return an error union" {
    const Namespace = struct {
        fn example() void {}
    };

    // Uncomment to trigger a compile-time error!
    //_ = errorType(Namespace.example);
}
