const Point = @import("point.zig");
const Range = @import("range.zig");

pub const Dimension = u16;

// zig fmt: off
/// A rectangular area in screen coordinates.
pub const Instance = struct {
    x: Range.Instance(Point.Coordinate),
    y: Range.Instance(Point.Coordinate),

    /// The top left corner of the bounding box.
    pub fn origin(self: Instance) Point.Instance {
        return .{ .x = self.x.min, .y = self.y.min };
    }

    /// Whether this bounding box overlaps with another.
    pub fn intersects(self: Instance, other: Instance) bool {
        return self.x.intersects(other.x) and self.y.intersects(other.y);
    }

    /// Whether this bounding box completely encloses another.
    pub fn encloses(self: Instance, other: Instance) bool {
        return self.x.encloses(other.x) and self.y.encloses(other.y);
    }

    /// Whether this bounding box contains the specified point.
    pub fn contains(self: Instance, point: Point.Instance) bool {
        return self.x.contains(point.x) and self.y.contains(point.y);
    }

    /// Whether this bounding box represents a unit square in Another World's rendering algorithm.
    pub fn isUnit(self: Instance) bool {
        // Horizontal coordinates are undercounted in Another World's polygon data,
        // so a unit square has a width of 0 and a height of 1.
        return
            self.x.max - self.x.min == 0 and
            self.y.max - self.y.min == 1;
    }
};
// zig fmt: on

pub fn new(min_x: Point.Coordinate, min_y: Point.Coordinate, max_x: Point.Coordinate, max_y: Point.Coordinate) Instance {
    return .{
        .x = .{ .min = min_x, .max = max_x },
        .y = .{ .min = min_y, .max = max_y },
    };
}

/// Creates a new bounding box of the specified width and height centered on the specified location.
pub fn centeredOn(center: Point.Instance, width: Dimension, height: Dimension) Instance {
    var self: Instance = undefined;

    // TODO: add tests for wrap-on-overflow
    self.x.min = center.x -% @intCast(Point.Coordinate, width / 2);
    self.y.min = center.y -% @intCast(Point.Coordinate, height / 2);

    self.x.max = self.x.min +% @intCast(Point.Coordinate, width);
    self.y.max = self.y.min +% @intCast(Point.Coordinate, height);

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

test "centeredOn creates correct bounding box" {
    const bb = centeredOn(.{ .x = 80, .y = 40 }, 320, 200);

    testing.expectEqual(-80, bb.x.min);
    testing.expectEqual(-60, bb.y.min);
    testing.expectEqual(240, bb.x.max);
    testing.expectEqual(140, bb.y.max);
}

test "origin returns expected origin" {
    const bb = Instance{
        .x = .{ .min = 160, .max = 320 },
        .y = .{ .min = 100, .max = 200 },
    };
    testing.expectEqual(.{ .x = 160, .y = 100 }, bb.origin());
}

test "intersects returns true for overlapping rectangles" {
    const reference = new(0, 0, 319, 199);

    const touching_top_left = new(-4, -4, 0, 0);
    const touching_bottom_right = new(319, 199, 320, 200);

    const touching_left_edge = new(-4, 0, 0, 199);
    const touching_right_edge = new(319, 0, 324, 199);
    const touching_top_edge = new(0, -4, 319, 0);
    const touching_bottom_edge = new(0, 199, 319, 204);

    const completely_enclosed = new(160, 100, 200, 120);
    const completely_encloses = new(-200, -200, 400, 400);

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
    const reference = new(0, 0, 319, 199);

    const completely_enclosed = new(160, 100, 200, 120);
    const equal = reference;

    const overlapping = new(-4, 4, 240, 10);
    const completely_encloses = new(-200, -200, 400, 400);
    const completely_disjoint = new(-5000, -5000, -4000, -4000);

    testing.expectEqual(true, reference.encloses(completely_enclosed));
    testing.expectEqual(true, reference.encloses(equal));

    testing.expectEqual(false, reference.encloses(overlapping));
    testing.expectEqual(false, reference.encloses(completely_disjoint));
    testing.expectEqual(false, reference.encloses(completely_encloses));
}

test "intersects returns false for disjoint rectangles" {
    const reference = new(0, 0, 319, 199);

    const not_quite_touching_top_left = new(-4, -4, -1, -1);
    const not_quite_touching_bottom_left = new(320, 200, 324, 204);

    const not_quite_touching_left_edge = new(-4, 0, -1, 199);
    const not_quite_touching_right_edge = new(320, 0, 324, 199);
    const not_quite_touching_top_edge = new(0, -4, 319, -1);
    const not_quite_touching_bottom_edge = new(0, 200, 319, 204);

    const completely_disjoint = new(-5000, -5000, -4000, -4000);

    expectIntersects(false, reference, not_quite_touching_top_left);
    expectIntersects(false, reference, not_quite_touching_bottom_left);
    expectIntersects(false, reference, not_quite_touching_left_edge);
    expectIntersects(false, reference, not_quite_touching_right_edge);
    expectIntersects(false, reference, not_quite_touching_top_edge);
    expectIntersects(false, reference, not_quite_touching_bottom_edge);
    expectIntersects(false, reference, completely_disjoint);
}

test "contains returns true for points within bounds" {
    const reference = new(0, 0, 319, 199);

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
    const reference = new(0, 0, 319, 199);

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
    const bb = new(160, 100, 160, 101);
    testing.expectEqual(true, bb.isUnit());
}

test "isUnit returns false for 1-width, 1-height bounding box" {
    const bb = new(160, 100, 161, 101);
    testing.expectEqual(false, bb.isUnit());
}

test "isUnit returns false for 0-width, 0-height bounding box" {
    const bb = new(160, 100, 160, 100);
    testing.expectEqual(false, bb.isUnit());
}
