const math = @import("std").math;

/// Defines a closed range of integers from a minimum up to *and including* a maximum value.
/// `min` and `max will be flipped if necessary to enforce that `min` <= `max`.
pub fn new(comptime Integer: type, min: anytype, max: Integer) Instance(Integer) {
    if (min <= max) {
        return .{ .min = min, .max = max };
    } else {
        return .{ .min = max, .max = min };
    }
}

/// Defines a closed range of integers from a minimum up to *and including* a maximum value.
/// Unlike `new`, this does not enforce that `min <= max`.
pub fn unchecked(comptime Integer: type, min: Integer, max: Integer) Instance(Integer) {
    return .{ .min = min, .max = max };
}

/// Defines the type for a range of integers from a minimum up to and including a maximum value.
pub fn Instance(comptime Integer: type) type {
    return struct {
        min: Integer,
        max: Integer,

        const Self = @This();

        /// Whether this range contains the specified value.
        pub fn contains(self: Self, value: Integer) bool {
            return value >= self.min and value <= self.max;
        }

        /// Whether this range intersects with another.
        pub fn intersects(self: Self, other: Self) bool {
            return self.min <= other.max and self.max >= other.min;
        }

        /// Whether this range completely encloses another.
        pub fn encloses(self: Self, other: Self) bool {
            return self.min <= other.min and self.max >= other.max;
        }

        /// Returns the intersection of two ranges.
        /// Returns null if the two ranges do not intersect.
        pub fn intersection(self: Self, other: Self) ?Self {
            const inter = Self{
                .min = math.max(self.min, other.min),
                .max = math.min(self.max, other.max),
            };

            return if (inter.min <= inter.max) inter else null;
        }
    };
}

// -- Tests --

const Examples = struct {
    const reference = new(isize, -10, 10);

    const enclosed = new(isize, -5, 5);
    const enclosing = new(isize, -15, 15);

    const overlapping_start = new(isize, -15, -5);
    const overlapping_end = new(isize, 5, 15);

    const touching_start = new(isize, -15, -10);
    const touching_end = new(isize, 10, 15);

    const disjoint = new(isize, -20, -11);
};

const testing = @import("../utils/testing.zig");

test "new returns range of expected type with expected values" {
    const range = Examples.reference;

    try testing.expectEqual(-10, range.min);
    try testing.expectEqual(10, range.max);
    try testing.expectEqual(isize, @TypeOf(range.min));
    try testing.expectEqual(isize, @TypeOf(range.max));
}

test "new reverses order of operands to ensure min < max" {
    const range = new(isize, 10, -10);
    try testing.expectEqual(-10, range.min);
    try testing.expectEqual(10, range.max);
}

test "unchecked leaves order of operands alone" {
    const range = unchecked(isize, 10, -10);
    try testing.expectEqual(10, range.min);
    try testing.expectEqual(-10, range.max);
}

test "contains returns true for values within range and false for values outside it" {
    const range = Examples.reference;

    try testing.expectEqual(true, range.contains(-10));
    try testing.expectEqual(true, range.contains(0));
    try testing.expectEqual(true, range.contains(10));

    try testing.expectEqual(false, range.contains(-11));
    try testing.expectEqual(false, range.contains(11));
}

fn expectIntersects(expectation: bool, range1: anytype, range2: @TypeOf(range1)) !void {
    // Intersects is commutative.
    try testing.expectEqual(expectation, range1.intersects(range2));
    try testing.expectEqual(expectation, range2.intersects(range1));
}

test "intersects returns true for ranges that intersect and false for ranges that don't intersect" {
    try expectIntersects(true, Examples.reference, Examples.reference);
    try expectIntersects(true, Examples.reference, Examples.enclosed);
    try expectIntersects(true, Examples.reference, Examples.enclosing);
    try expectIntersects(true, Examples.reference, Examples.overlapping_start);
    try expectIntersects(true, Examples.reference, Examples.overlapping_end);
    try expectIntersects(true, Examples.reference, Examples.touching_start);
    try expectIntersects(true, Examples.reference, Examples.touching_end);

    try expectIntersects(false, Examples.reference, Examples.disjoint);
}

test "intersects returns true for ranges that completely enclose another and false otherwise" {
    try testing.expectEqual(true, Examples.reference.encloses(Examples.reference));
    try testing.expectEqual(true, Examples.reference.encloses(Examples.enclosed));

    try testing.expectEqual(false, Examples.reference.encloses(Examples.enclosing));
    try testing.expectEqual(false, Examples.reference.encloses(Examples.overlapping_start));
    try testing.expectEqual(false, Examples.reference.encloses(Examples.overlapping_end));
    try testing.expectEqual(false, Examples.reference.encloses(Examples.touching_start));
    try testing.expectEqual(false, Examples.reference.encloses(Examples.touching_end));
    try testing.expectEqual(false, Examples.reference.encloses(Examples.disjoint));
}

fn expectIntersection(expectation: anytype, range1: anytype, range2: @TypeOf(range1)) !void {
    // Intersection is commutative
    try testing.expectEqual(expectation, range1.intersection(range2));
    try testing.expectEqual(expectation, range2.intersection(range1));
}

test "intersection returns intersection of two ranges or null for disjoint ranges" {
    try expectIntersection(Examples.reference, Examples.reference, Examples.reference);
    try expectIntersection(Examples.enclosed, Examples.reference, Examples.enclosed);
    try expectIntersection(Examples.reference, Examples.reference, Examples.enclosing);

    try expectIntersection(.{ .min = -10, .max = -5 }, Examples.reference, Examples.overlapping_start);
    try expectIntersection(.{ .min = 5, .max = 10 }, Examples.reference, Examples.overlapping_end);
    try expectIntersection(.{ .min = -10, .max = -10 }, Examples.reference, Examples.touching_start);
    try expectIntersection(.{ .min = 10, .max = 10 }, Examples.reference, Examples.touching_end);

    try expectIntersection(null, Examples.reference, Examples.disjoint);
}
