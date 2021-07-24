const testing = @import("std").testing;
const TagType = @import("std").meta.TagType;

/// Wrap to provide better type inference.
/// With the default std.testing implementation, `actual` is constrained to the type of `expected`:
/// This makes things like `assertEqual(2, variablename)` fail to compile, because `variablename`
/// is coerced to a `comptime_int` instead of `2` being coerced to the type of `variablename`.
pub fn expectEqual(expected: anytype, actual: anytype) !void {
    return testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}

/// Test that a tagged union value has the expected tag.
pub fn expectEqualTags(expected: anytype, actual: anytype) !void {
    const Tag = TagType(@TypeOf(actual));
    return testing.expectEqual(@as(Tag, expected), @as(Tag, actual));
}

pub const expect = testing.expect;
pub const expectError = testing.expectError;
pub const expectEqualSlices = testing.expectEqualSlices;
pub const expectEqualStrings = testing.expectEqualStrings;

pub const allocator = testing.allocator;
pub const failing_allocator = testing.failing_allocator;

// -- Tests --

test "expectEqual correctly coerces types that std.testing.expectEqual does not" {
    const int_value: u8 = 2;
    try expectEqual(2, int_value);

    const optional_value: ?u8 = null;
    try expectEqual(null, optional_value);

    const Enum = enum { One, Two };
    const enum_value = Enum.One;
    try expectEqual(.One, enum_value);
}

test "expectEqualTags correctly coerces union values to tags" {
    const Union = union(enum) {
        foo: u8,
        bar: u8,
    };

    const is_foo: Union = .{ .foo = 1 };
    const is_bar: Union = .{ .bar = 2 };

    try expectEqualTags(.foo, is_foo);
    try expectEqualTags(.bar, is_bar);

    // Uncomment to 💥
    // try expectEqualTags(.bar, is_foo);
    // try expectEqualTags(.foo, is_bar);
}

const Error = error{FakeError};
fn returnError() Error!void {
    return error.FakeError;
}

test "expectError passes through correctly" {
    try expectError(error.FakeError, returnError());
}
