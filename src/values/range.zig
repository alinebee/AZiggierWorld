const math = @import("std").math;

/// Defines the type for a range of integers from a minimum up to and including a maximum value.
pub fn Range(comptime Integer: type) type {
    return struct {
        min: Integer,
        max: Integer,

        const Self = @This();

        pub fn init(min: anytype, max: Integer) Self {
            if (min <= max) {
                return .{ .min = min, .max = max };
            } else {
                return .{ .min = max, .max = min };
            }
        }

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
    const reference = Range(isize).init(-10, 10);

    const enclosed = Range(isize).init(-5, 5);
    const enclosing = Range(isize).init(-15, 15);

    const overlapping_start = Range(isize).init(-15, -5);
    const overlapping_end = Range(isize).init(5, 15);

    const touching_start = Range(isize).init(-15, -10);
    const touching_end = Range(isize).init(10, 15);

    const disjoint = Range(isize).init(-20, -11);
};

const testing = @import("../utils/testing.zig");

test "init returns range of expected type with expected values" {
    const range = Examples.reference;

    try testing.expectEqual(-10, range.min);
    try testing.expectEqual(10, range.max);
    try testing.expectEqual(isize, @TypeOf(range.min));
    try testing.expectEqual(isize, @TypeOf(range.max));
}

test "init reverses order of operands to ensure min < max" {
    const range = Range(isize).init(10, -10);
    try testing.expectEqual(-10, range.min);
    try testing.expectEqual(10, range.max);
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
