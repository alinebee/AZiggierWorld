const testing = @import("std").testing;

/// Wrap to provide better type inference.
/// With the default std.testing implementation, `actual` is constrained to the type of `expected`:
/// This makes things like `assertEqual(2, variablename)` fail to compile, because `variablename`
/// is coerced to a `comptime_int` instead of `2` being coerced to the type of `variablename`.
pub fn expectEqual(expected: anytype, actual: anytype) void {
    testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}

pub const expectError = testing.expectError;

// -- Tests --

test "expectEqual correctly coerces types that std.testing.expectEqual does not" {
    const int_value: u8 = 2;
    expectEqual(2, int_value);

    const optional_value: ?u8 = null;
    expectEqual(null, optional_value);

    const Enum = enum { One, Two };
    const enum_value = Enum.One;
    expectEqual(.One, enum_value);
}

const Error = error { FakeError };
fn return_error() Error!void {
    return error.FakeError;
}

test "expectError passes through correctly" {
    expectError(Error.FakeError, return_error());
}