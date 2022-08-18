const anotherworld = @import("../anotherworld.zig");

/// Defines an X,Y point in screen space.
pub const Point = struct {
    /// The X position in virtual 320x200 pixels, starting from the left edge of the screen.
    x: Coordinate,

    /// The Y position in virtual 320x200 pixels, starting from the top edge of the screen.
    y: Coordinate,

    const Self = @This();

    /// Add two points together, wrapping on overflow.
    pub fn adding(self: Self, other: Self) Self {
        return .{
            .x = self.x +% other.x,
            .y = self.y +% other.y,
        };
    }

    pub fn subtracting(self: Self, other: Self) Self {
        return .{
            .x = self.x -% other.x,
            .y = self.y -% other.y,
        };
    }

    // - Exported constants -

    pub const Coordinate = i16;

    pub const zero = Self{ .x = 0, .y = 0 };
};

// -- Tests --

const testing = @import("utils").testing;
const math = @import("std").math;

const max_coord = math.maxInt(Point.Coordinate);
const min_coord = math.minInt(Point.Coordinate);

const base = Point.zero;
const positive = Point{ .x = 10, .y = 10 };
const negative = Point{ .x = -10, .y = -10 };
const max = Point{ .x = max_coord, .y = max_coord };
const min = Point{ .x = min_coord, .y = min_coord };

test "adding adds points A and B together, wrapping on overflow" {
    try testing.expectEqual(.{ .x = 10, .y = 10 }, base.adding(positive));
    try testing.expectEqual(.{ .x = -10, .y = -10 }, base.adding(negative));

    try testing.expectEqual(.{ .x = min_coord + 9, .y = min_coord + 9 }, max.adding(positive));
    try testing.expectEqual(.{ .x = max_coord - 9, .y = max_coord - 9 }, min.adding(negative));
}

test "substracting substracts point B from point A, wrapping on overflow" {
    try testing.expectEqual(.{ .x = -10, .y = -10 }, base.subtracting(positive));
    try testing.expectEqual(.{ .x = 10, .y = 10 }, base.subtracting(negative));

    try testing.expectEqual(.{ .x = max_coord - 9, .y = max_coord - 9 }, min.subtracting(positive));
    try testing.expectEqual(.{ .x = min_coord + 9, .y = min_coord + 9 }, max.subtracting(negative));
}
