const Point = @import("../values/point.zig");

pub const Dimension = u16;

// zig fmt: off
/// A rectangular area in screen coordinates.
pub const Instance = struct {
    min_x: Point.Coordinate,
    max_x: Point.Coordinate,
    min_y: Point.Coordinate,
    max_y: Point.Coordinate,

    /// The top left corner of the bounding box.
    pub fn origin(self: Instance) Point.Instance {
        return .{ .x = self.min_x, .y = self.min_y };
    }

    /// Whether this bounding box overlaps with another.
    pub fn intersects(self: Instance, other: Instance) bool {
        return
            self.min_x <= other.max_x and
            self.min_y <= other.max_y and
            self.max_x >= other.min_x and
            self.max_y >= other.min_y;
    }

    /// Whether this bounding box completely encloses another.
    pub fn encloses(self: Instance, other: Instance) bool {
        return
            self.min_x <= other.min_x and
            self.min_y <= other.min_y and
            self.max_x >= other.max_x and
            self.max_y >= other.max_y;
    }

    /// Whether this bounding box contains the specified point.
    pub fn contains(self: Instance, point: Point.Instance) bool {
        return
            point.x >= self.min_x and
            point.y >= self.min_y and
            point.x <= self.max_x and
            point.y <= self.max_y;
    }

    pub fn isUnit(self: Instance) bool {
        // Horizontal coordinates are undercounted in Another World's polygon data.
        return
            self.max_x - self.min_x == 0 and
            self.max_y - self.min_y == 1;
    }
};
// zig fmt: on

/// Creates a new bounding box of the specified width and height, centered on the specified location.
pub fn new(center: Point.Instance, width: Dimension, height: Dimension) Instance {
    var self: Instance = undefined;

    // TODO: add tests for wrap-on-overflow
    self.min_x = center.x -% @intCast(Point.Coordinate, width / 2);
    self.min_y = center.y -% @intCast(Point.Coordinate, height / 2);

    self.max_x = self.min_x +% @intCast(Point.Coordinate, width);
    self.max_y = self.min_y +% @intCast(Point.Coordinate, height);

    return self;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

fn expectIntersects(expectation: bool, bb1: Instance, bb2: Instance) void {
    testing.expectEqual(expectation, bb1.intersects(bb2));
    testing.expectEqual(expectation, bb2.intersects(bb1));
}

fn expectContains(expectation: bool, bb: Instance, point: Point.Instance) void {
    testing.expectEqual(expectation, bb.contains(point));
}

test "new creates correct bounding box" {
    const bb = new(.{ .x = 80, .y = 40 }, 320, 200);

    testing.expectEqual(-80, bb.min_x);
    testing.expectEqual(-60, bb.min_y);
    testing.expectEqual(240, bb.max_x);
    testing.expectEqual(140, bb.max_y);
}

test "origin returns expected origin" {
    const bb = Instance{ .min_x = 160, .min_y = 100, .max_x = 320, .max_y = 200 };
    testing.expectEqual(.{ .x = 160, .y = 100 }, bb.origin());
}

test "intersects returns true for overlapping rectangles" {
    const reference = Instance{ .min_x = 0, .min_y = 0, .max_x = 319, .max_y = 199 };

    const touching_top_left = Instance{ .min_x = -4, .min_y = -4, .max_x = 0, .max_y = 0 };
    const touching_bottom_right = Instance{ .min_x = 319, .min_y = 199, .max_x = 320, .max_y = 200 };

    const touching_left_edge = Instance{ .min_x = -4, .min_y = 0, .max_x = 0, .max_y = 199 };
    const touching_right_edge = Instance{ .min_x = 319, .min_y = 0, .max_x = 324, .max_y = 199 };
    const touching_top_edge = Instance{ .min_x = 0, .min_y = -4, .max_x = 319, .max_y = 0 };
    const touching_bottom_edge = Instance{ .min_x = 0, .min_y = 199, .max_x = 319, .max_y = 204 };

    const completely_enclosed = Instance{ .min_x = 160, .min_y = 100, .max_x = 200, .max_y = 120 };
    const completely_encloses = Instance{ .min_x = -200, .min_y = -200, .max_x = 400, .max_y = 400 };

    expectIntersects(true, reference, touching_top_left);
    expectIntersects(true, reference, touching_bottom_right);
    expectIntersects(true, reference, touching_left_edge);
    expectIntersects(true, reference, touching_right_edge);
    expectIntersects(true, reference, touching_top_edge);
    expectIntersects(true, reference, touching_bottom_edge);
    expectIntersects(true, reference, completely_enclosed);
    expectIntersects(true, reference, completely_encloses);
}

test "encloses returns true for completely enclosed rectangles and false for others" {
    const reference = Instance{ .min_x = 0, .min_y = 0, .max_x = 319, .max_y = 199 };

    const completely_enclosed = Instance{ .min_x = 160, .min_y = 100, .max_x = 200, .max_y = 120 };
    const equal = reference;

    const overlapping = Instance{ .min_x = -4, .min_y = 4, .max_x = 240, .max_y = 10 };
    const completely_encloses = Instance{ .min_x = -200, .min_y = -200, .max_x = 400, .max_y = 400 };
    const completely_disjoint = Instance{ .min_x = -5000, .min_y = -5000, .max_x = -4000, .max_y = -4000 };

    testing.expectEqual(true, reference.encloses(completely_enclosed));
    testing.expectEqual(true, reference.encloses(equal));

    testing.expectEqual(false, reference.encloses(overlapping));
    testing.expectEqual(false, reference.encloses(completely_disjoint));
    testing.expectEqual(false, reference.encloses(completely_encloses));
}

test "intersects returns false for disjoint rectangles" {
    const reference = Instance{ .min_x = 0, .min_y = 0, .max_x = 319, .max_y = 199 };

    const not_quite_touching_top_left = Instance{ .min_x = -4, .min_y = -4, .max_x = -1, .max_y = -1 };
    const not_quite_touching_bottom_left = Instance{ .min_x = 320, .min_y = 200, .max_x = 324, .max_y = 204 };

    const not_quite_touching_left_edge = Instance{ .min_x = -4, .min_y = 0, .max_x = -1, .max_y = 199 };
    const not_quite_touching_right_edge = Instance{ .min_x = 320, .min_y = 0, .max_x = 324, .max_y = 199 };
    const not_quite_touching_top_edge = Instance{ .min_x = 0, .min_y = -4, .max_x = 319, .max_y = -1 };
    const not_quite_touching_bottom_edge = Instance{ .min_x = 0, .min_y = 200, .max_x = 319, .max_y = 204 };

    const completely_disjoint = Instance{ .min_x = -5000, .min_y = -5000, .max_x = -4000, .max_y = -4000 };

    expectIntersects(false, reference, not_quite_touching_top_left);
    expectIntersects(false, reference, not_quite_touching_bottom_left);
    expectIntersects(false, reference, not_quite_touching_left_edge);
    expectIntersects(false, reference, not_quite_touching_right_edge);
    expectIntersects(false, reference, not_quite_touching_top_edge);
    expectIntersects(false, reference, not_quite_touching_bottom_edge);
    expectIntersects(false, reference, completely_disjoint);
}

test "contains returns true for points within bounds" {
    const reference = Instance{ .min_x = 0, .min_y = 0, .max_x = 319, .max_y = 199 };

    const top_left_corner = Point.Instance{ .x = 0, .y = 0 };
    const bottom_right_corner = Point.Instance{ .x = 319, .y = 199 };
    const left_edge = Point.Instance{ .x = 0, .y = 100 };
    const right_edge = Point.Instance{ .x = 319, .y = 100 };
    const top_edge = Point.Instance{ .x = 160, .y = 0 };
    const bottom_edge = Point.Instance{ .x = 160, .y = 199 };
    const center = Point.Instance{ .x = 160, .y = 100 };

    expectContains(true, reference, top_left_corner);
    expectContains(true, reference, bottom_right_corner);
    expectContains(true, reference, left_edge);
    expectContains(true, reference, right_edge);
    expectContains(true, reference, top_edge);
    expectContains(true, reference, bottom_edge);
    expectContains(true, reference, center);
}

test "contains returns false for points out of bounds" {
    const reference = Instance{ .min_x = 0, .min_y = 0, .max_x = 319, .max_y = 199 };

    const not_quite_top_left_corner = Point.Instance{ .x = -1, .y = -1 };
    const not_quite_bottom_rightcorner = Point.Instance{ .x = 320, .y = 200 };
    const not_quite_left_edge = Point.Instance{ .x = -1, .y = 100 };
    const not_quite_right_edge = Point.Instance{ .x = 320, .y = 100 };
    const not_quite_top_edge = Point.Instance{ .x = 160, .y = -1 };
    const not_quite_bottom_edge = Point.Instance{ .x = 160, .y = 200 };
    const somewhere_else_entirely = Point.Instance{ .x = -5000, .y = -5000 };

    expectContains(false, reference, not_quite_top_left_corner);
    expectContains(false, reference, not_quite_bottom_rightcorner);
    expectContains(false, reference, not_quite_left_edge);
    expectContains(false, reference, not_quite_right_edge);
    expectContains(false, reference, not_quite_top_edge);
    expectContains(false, reference, not_quite_bottom_edge);
    expectContains(false, reference, somewhere_else_entirely);
}

test "isUnit returns true for 0-width, 1-height bounding box" {
    const bb = Instance{ .min_x = 160, .min_y = 100, .max_x = 160, .max_y = 101 };
    testing.expectEqual(true, bb.isUnit());
}

test "isUnit returns false for 1-width, 1-height bounding box" {
    const bb = Instance{ .min_x = 160, .min_y = 100, .max_x = 161, .max_y = 101 };
    testing.expectEqual(false, bb.isUnit());
}

test "isUnit returns false for 0-width, 0-height bounding box" {
    const bb = Instance{ .min_x = 160, .min_y = 100, .max_x = 160, .max_y = 100 };
    testing.expectEqual(false, bb.isUnit());
}
