const Point = @import("../values/point.zig");

pub const Dimension = u16;

/// A rectangular area in screen coordinates.
pub const Instance = struct {
    minX: Point.Coordinate,
    maxX: Point.Coordinate,
    minY: Point.Coordinate,
    maxY: Point.Coordinate,

    /// The top left corner of the bounding box.
    pub fn origin(self: Instance) Point.Instance {
        return .{ .x = self.minX, .y = self.minY };
    }

    /// Whether this bounding box overlaps with another.
    pub fn intersects(self: Instance, other: Instance) bool {
        return self.minX <= other.maxX and
            self.minY <= other.maxY and
            self.maxX >= other.minX and
            self.maxY >= other.minY;
    }

    pub fn isUnit(self: Instance) bool {
        // Horizontal coordinates are undercounted in Another World's polygon data.
        return self.maxX - self.minX == 0 and self.maxY - self.minY == 1;
    }
};

/// Creates a new bounding box of the specified width and height, centered on the specified location.
pub fn new(center: Point.Instance, width: Dimension, height: Dimension) Instance {
    var self: Instance = undefined;

    // TODO: add tests for wrap-on-overflow
    self.minX = center.x -% @intCast(Point.Coordinate, width / 2);
    self.minY = center.y -% @intCast(Point.Coordinate, height / 2);

    self.maxX = self.minX +% @intCast(Point.Coordinate, width);
    self.maxY = self.minY +% @intCast(Point.Coordinate, height);

    return self;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

fn expectIntersects(expectation: bool, bb1: Instance, bb2: Instance) void {
    testing.expectEqual(expectation, bb1.intersects(bb2));
    testing.expectEqual(expectation, bb2.intersects(bb1));
}

test "new creates correct bounding box" {
    const bb = new(.{ .x = 80, .y = 40 }, 320, 200);

    testing.expectEqual(-80, bb.minX);
    testing.expectEqual(-60, bb.minY);
    testing.expectEqual(240, bb.maxX);
    testing.expectEqual(140, bb.maxY);
}

test "origin returns expected origin" {
    const bb = Instance{ .minX = 160, .minY = 100, .maxX = 320, .maxY = 200 };
    testing.expectEqual(.{ .x = 160, .y = 100 }, bb.origin());
}

test "intersects returns true for overlapping rectangles" {
    const reference = Instance{ .minX = 0, .minY = 0, .maxX = 319, .maxY = 199 };

    const touching_top_left = Instance{ .minX = -4, .minY = -4, .maxX = 0, .maxY = 0 };
    const touching_bottom_right = Instance{ .minX = 319, .minY = 199, .maxX = 320, .maxY = 200 };

    const touching_left_edge = Instance{ .minX = -4, .minY = 0, .maxX = 0, .maxY = 199 };
    const touching_right_edge = Instance{ .minX = 319, .minY = 0, .maxX = 324, .maxY = 199 };
    const touching_top_edge = Instance{ .minX = 0, .minY = -4, .maxX = 319, .maxY = 0 };
    const touching_bottom_edge = Instance{ .minX = 0, .minY = 199, .maxX = 319, .maxY = 204 };

    const completely_enclosed = Instance{ .minX = 160, .minY = 100, .maxX = 200, .maxY = 120 };
    const completely_encloses = Instance{ .minX = -200, .minY = -200, .maxX = 400, .maxY = 400 };

    expectIntersects(true, reference, touching_top_left);
    expectIntersects(true, reference, touching_bottom_right);
    expectIntersects(true, reference, touching_left_edge);
    expectIntersects(true, reference, touching_right_edge);
    expectIntersects(true, reference, touching_top_edge);
    expectIntersects(true, reference, touching_bottom_edge);
    expectIntersects(true, reference, completely_enclosed);
    expectIntersects(true, reference, completely_encloses);
}

test "intersects returns false for disjoint rectangles" {
    const reference = Instance{ .minX = 0, .minY = 0, .maxX = 319, .maxY = 199 };

    const not_quite_touching_top_left = Instance{ .minX = -4, .minY = -4, .maxX = -1, .maxY = -1 };
    const not_quite_touching_bottom_left = Instance{ .minX = 320, .minY = 200, .maxX = 324, .maxY = 204 };

    const not_quite_touching_left_edge = Instance{ .minX = -4, .minY = 0, .maxX = -1, .maxY = 199 };
    const not_quite_touching_right_edge = Instance{ .minX = 320, .minY = 0, .maxX = 324, .maxY = 199 };
    const not_quite_touching_top_edge = Instance{ .minX = 0, .minY = -4, .maxX = 319, .maxY = -1 };
    const not_quite_touching_bottom_edge = Instance{ .minX = 0, .minY = 200, .maxX = 319, .maxY = 204 };

    const completely_disjoint = Instance{ .minX = -5000, .minY = -5000, .maxX = -4000, .maxY = -4000 };

    expectIntersects(false, reference, not_quite_touching_top_left);
    expectIntersects(false, reference, not_quite_touching_bottom_left);
    expectIntersects(false, reference, not_quite_touching_left_edge);
    expectIntersects(false, reference, not_quite_touching_right_edge);
    expectIntersects(false, reference, not_quite_touching_top_edge);
    expectIntersects(false, reference, not_quite_touching_bottom_edge);
    expectIntersects(false, reference, completely_disjoint);
}

test "isUnit returns true for 0-width, 1-height bounding box" {
    const bb = Instance{ .minX = 160, .minY = 100, .maxX = 160, .maxY = 101 };
    testing.expectEqual(true, bb.isUnit());
}

test "isUnit returns false for 1-width, 1-height bounding box" {
    const bb = Instance{ .minX = 160, .minY = 100, .maxX = 161, .maxY = 101 };
    testing.expectEqual(false, bb.isUnit());
}

test "isUnit returns false for 0-width, 0-height bounding box" {
    const bb = Instance{ .minX = 160, .minY = 100, .maxX = 160, .maxY = 100 };
    testing.expectEqual(false, bb.isUnit());
}
