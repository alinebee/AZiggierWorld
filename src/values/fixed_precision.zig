/// A signed fixed-point number with 16 bits of precision for the whole part
/// and 16 bits of precision for the fraction. Used for rendering polygons
/// without needing floating-point numbers.
pub const Instance = struct {
    raw: i32,

    const Self = @This();

    /// The whole component of the number.
    pub fn whole(self: Self) i16 {
        return @truncate(i16, self.raw >> 16);
    }

    /// The fractional component of the number.
    fn fraction(self: Self) u16 {
        return @truncate(u16, @bitCast(u32, self.raw));
    }

    /// Set a new fractional component of the number.
    pub fn setFraction(self: *Self, _fraction: u16) void {
        self.raw = @bitCast(i32, (@bitCast(u32, self.raw) & 0xFFFF_0000) | _fraction);
    }

    /// Add another fixed-precision number to this one.
    pub fn add(self: *Self, other: Self) void {
        self.raw +%= other.raw;
    }
};

/// Create a new fixed precision value from a whole number.
pub fn new(_whole: i16) Instance {
    return .{ .raw = @as(i32, _whole) << 16 };
}

// -- Testing --

const testing = @import("../utils/testing.zig");

fn raw(pattern: u32) i32 {
    return @bitCast(i32, pattern);
}

test "new creates expected 32-bit value from 16-bit value, preserving sign" {
    const positive = new(32767);
    const negative = new(-32768);

    try testing.expectEqual(raw(0b0111_1111_1111_1111_0000_0000_0000_0000), positive.raw);
    try testing.expectEqual(raw(0b1000_0000_0000_0000_0000_0000_0000_0000), negative.raw);
}

test "whole returns whole part of value, preserving sign" {
    const positive = new(32767);
    const negative = new(-32768);

    try testing.expectEqual(32767, positive.whole());
    try testing.expectEqual(-32768, negative.whole());
}

test "fraction returns fractional part of value" {
    const value = Instance{ .raw = raw(0b1111_1111_1111_1111_0101_1010_0101_1010) };

    try testing.expectEqual(0b0101_1010_0101_1010, value.fraction());
}

test "setFraction sets expected value" {
    var value = Instance{ .raw = raw(0b1111_1111_1111_1111_0101_1010_0101_1010) };

    value.setFraction(0b0011_1100_0011_1100);

    try testing.expectEqual(raw(0b1111_1111_1111_1111_0011_1100_0011_1100), value.raw);
}

test "add increments fractional component into whole component" {
    var value = new(2);
    value.setFraction(65535);

    var other = new(1);
    other.setFraction(1);

    value.add(other);

    try testing.expectEqual(4, value.whole());
    try testing.expectEqual(0, value.fraction());
}

test "add wraps on overflow" {
    var value = Instance{ .raw = raw(0b0111_1111_1111_1111_1111_1111_1111_1111) };
    const other = Instance{ .raw = raw(0b0000_0000_0000_0000_0000_0000_0000_0001) };

    value.add(other);

    try testing.expectEqual(raw(0b1000_0000_0000_0000_0000_0000_0000_0000), value.raw);
}
