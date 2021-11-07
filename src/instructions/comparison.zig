const Register = @import("../values/register.zig");
const intToEnum = @import("../utils/introspection.zig").intToEnum;

/// A raw JumpConditional comparison as it is represented in bytecode.
pub const Raw = u3;

/// The supported comparisons for a JumpConditional instruction.
pub const Enum = enum(Raw) {
    equal,
    not_equal,
    greater_than,
    greater_than_or_equal_to,
    less_than,
    less_than_or_equal_to,

    pub fn compare(self: Enum, lhs: Register.Signed, rhs: Register.Signed) bool {
        return switch (self) {
            .equal => lhs == rhs,
            .not_equal => lhs != rhs,
            .greater_than => lhs > rhs,
            .greater_than_or_equal_to => lhs >= rhs,
            .less_than => lhs < rhs,
            .less_than_or_equal_to => lhs <= rhs,
        };
    }
};

pub const Error = error{
    /// The bytecode specified an unknown JumpConditional comparison.
    InvalidJumpComparison,
};

/// Parse a valid comparison type from a raw bytecode value.
/// Returns error.InvalidJumpComparison if the value could not be parsed.
pub fn parse(raw: Raw) Error!Enum {
    return intToEnum(Enum, raw) catch error.InvalidJumpComparison;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse parses raw comparison values correctly" {
    try testing.expectEqual(.equal, parse(0b000));
    try testing.expectEqual(.not_equal, parse(0b001));
    try testing.expectEqual(.greater_than, parse(0b010));
    try testing.expectEqual(.greater_than_or_equal_to, parse(0b011));
    try testing.expectEqual(.less_than, parse(0b100));
    try testing.expectEqual(.less_than_or_equal_to, parse(0b101));

    try testing.expectError(error.InvalidJumpComparison, parse(0b110));
    try testing.expectError(error.InvalidJumpComparison, parse(0b111));
}

test "equal compares correctly" {
    const comparison = Enum.equal;
    try testing.expectEqual(true, comparison.compare(1, 1));
    try testing.expectEqual(false, comparison.compare(1, -1));
}

test "not_equal compares correctly" {
    const comparison = Enum.not_equal;
    try testing.expectEqual(true, comparison.compare(1, -1));
    try testing.expectEqual(true, comparison.compare(-1, 1));
    try testing.expectEqual(false, comparison.compare(1, 1));
}

test "greater_than compares correctly" {
    const comparison = Enum.greater_than;
    try testing.expectEqual(true, comparison.compare(2, 1));
    try testing.expectEqual(false, comparison.compare(1, 1));
    try testing.expectEqual(false, comparison.compare(1, 2));
}

test "greater_than_or_equal_to compares correctly" {
    const comparison = Enum.greater_than_or_equal_to;
    try testing.expectEqual(true, comparison.compare(2, 1));
    try testing.expectEqual(true, comparison.compare(1, 1));
    try testing.expectEqual(false, comparison.compare(1, 2));
}

test "less_than compares correctly" {
    const comparison = Enum.less_than;
    try testing.expectEqual(true, comparison.compare(1, 2));
    try testing.expectEqual(false, comparison.compare(1, 1));
    try testing.expectEqual(false, comparison.compare(2, 1));
}

test "less_than_or_equal_to compares correctly" {
    const comparison = Enum.less_than_or_equal_to;
    try testing.expectEqual(true, comparison.compare(1, 2));
    try testing.expectEqual(true, comparison.compare(1, 1));
    try testing.expectEqual(false, comparison.compare(2, 1));
}
