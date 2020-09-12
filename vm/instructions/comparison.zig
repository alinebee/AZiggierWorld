const RegisterValue = @import("../machine.zig").RegisterValue;

/// A raw ConditionalJump comparison as it is represented in bytecode.
pub const Raw = u3;

/// The supported comparisons for a ConditionalJump instruction.
pub const Enum = enum(Raw) {
    equal,
    not_equal,
    greater_than,
    greater_than_or_equal_to,
    less_than,
    less_than_or_equal_to,

    pub fn compare(self: Enum, lhs: RegisterValue, rhs: RegisterValue) bool {
        return switch (self) {
            .equal                      => lhs == rhs,
            .not_equal                  => lhs != rhs,
            .greater_than               => lhs > rhs,
            .greater_than_or_equal_to   => lhs >= rhs,
            .less_than                  => lhs < rhs,
            .less_than_or_equal_to      => lhs <= rhs,
        };
    }
};

pub const Error = error {
    /// The bytecode specified an unknown ConditionalJump comparison.
    InvalidJumpComparison,
};

/// Parse a valid comparison type from a raw bytecode value.
/// Returns error.InvalidJumpComparison if the value could not be parsed.
pub fn parse(raw: Raw) Error!Enum {
    if (raw > @enumToInt(Enum.less_than_or_equal_to)) {
        return error.InvalidJumpComparison;
    }
    return @intToEnum(Enum, raw);
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "parse parses raw comparison values correctly" {
    testing.expectEqual(.equal,                     parse(0b000));
    testing.expectEqual(.not_equal,                 parse(0b001));
    testing.expectEqual(.greater_than,              parse(0b010));
    testing.expectEqual(.greater_than_or_equal_to,  parse(0b011));
    testing.expectEqual(.less_than,                 parse(0b100));
    testing.expectEqual(.less_than_or_equal_to,     parse(0b101));
    
    testing.expectError(error.InvalidJumpComparison, parse(0b110));
    testing.expectError(error.InvalidJumpComparison, parse(0b111));
}

test "equal compares correctly" {
    const comparison = Enum.equal;
    testing.expectEqual(true, comparison.compare(1, 1));
    testing.expectEqual(false, comparison.compare(1, -1));
}

test "not_equal compares correctly" {
    const comparison = Enum.not_equal;
    testing.expectEqual(true, comparison.compare(1, -1));
    testing.expectEqual(true, comparison.compare(-1, 1));
    testing.expectEqual(false, comparison.compare(1, 1));
}

test "greater_than compares correctly" {
    const comparison = Enum.greater_than;
    testing.expectEqual(true, comparison.compare(2, 1));
    testing.expectEqual(false, comparison.compare(1, 1));
    testing.expectEqual(false, comparison.compare(1, 2));
}

test "greater_than_or_equal_to compares correctly" {
    const comparison = Enum.greater_than_or_equal_to;
    testing.expectEqual(true, comparison.compare(2, 1));
    testing.expectEqual(true, comparison.compare(1, 1));
    testing.expectEqual(false, comparison.compare(1, 2));
}

test "less_than compares correctly" {
    const comparison = Enum.less_than;
    testing.expectEqual(true, comparison.compare(1, 2));
    testing.expectEqual(false, comparison.compare(1, 1));
    testing.expectEqual(false, comparison.compare(2, 1));
}

test "less_than_or_equal_to compares correctly" {
    const comparison = Enum.less_than_or_equal_to;
    testing.expectEqual(true, comparison.compare(1, 2));
    testing.expectEqual(true, comparison.compare(1, 1));
    testing.expectEqual(false, comparison.compare(2, 1));
}
