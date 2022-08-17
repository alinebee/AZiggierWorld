const Point = @import("point.zig").Point;
const Range = @import("range.zig").Range;

/// A rectangular area in screen coordinates.
pub const BoundingBox = struct {
    x: Range(Point.Coordinate),
    y: Range(Point.Coordinate),

    const Self = @This();

    /// Creates a new bounding box with the specified min and max coordinates (inclusive).
    pub fn init(min_x: Point.Coordinate, min_y: Point.Coordinate, max_x: Point.Coordinate, max_y: Point.Coordinate) Self {
        return .{
            .x = .{ .min = min_x, .max = max_x },
            .y = .{ .min = min_y, .max = max_y },
        };
    }

    /// Creates a new bounding box of the specified width and height centered on the specified location.
    pub fn centeredOn(center: Point, width: Dimension, height: Dimension) Self {
        var self: Self = undefined;

        const native_width = @as(isize, width);
        const native_height = @as(isize, height);

        const native_minx = @as(isize, center.x) -% @divTrunc(native_width, 2);
        const native_miny = @as(isize, center.y) -% @divTrunc(native_height, 2);

        // Note: this diverges from the reference implementation, which added
        // [width / 2] and [height / 2] to the center to get the max x and y.
        // Since division truncates, this would result in odd widths/heights
        // having a max 1 lower than it should be, potentially causing
        // polygons at the top/left screen edges to not be drawn when they should.
        // The behaviour below is more correct, but may cause the rendering to diverge
        // from the original in unwanted ways.
        const native_maxx = native_minx +% native_width;
        const native_maxy = native_miny +% native_height;

        self.x.min = @truncate(Point.Coordinate, native_minx);
        self.x.max = @truncate(Point.Coordinate, native_maxx);
        self.y.min = @truncate(Point.Coordinate, native_miny);
        self.y.max = @truncate(Point.Coordinate, native_maxy);

        return self;
    }

    /// The top left corner of the bounding box.
    pub fn origin(self: Self) Point {
        return .{ .x = self.x.min, .y = self.y.min };
    }

    /// Whether this bounding box overlaps with another.
    pub fn intersects(self: Self, other: Self) bool {
        return self.x.intersects(other.x) and self.y.intersects(other.y);
    }

    /// Whether this bounding box completely encloses another.
    pub fn encloses(self: Self, other: Self) bool {
        return self.x.encloses(other.x) and self.y.encloses(other.y);
    }

    /// Whether this bounding box contains the specified point.
    pub fn contains(self: Self, point: Point) bool {
        return self.x.contains(point.x) and self.y.contains(point.y);
    }

    /// Whether this bounding box represents a unit square in Another World's rendering algorithm.
    pub fn isUnit(self: Self) bool {
        // Horizontal coordinates are undercounted in Another World's polygon data,
        // so a unit square has a width of 0 and a height of 1.
        // zig fmt: off
        return
            self.x.max - self.x.min == 0 and
            self.y.max - self.y.min == 1;
        // zig fmt: on
    }

    // - Exported constants -

    pub const Dimension = u16;
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const math = @import("std").math;

fn expectIntersects(expectation: bool, bb1: BoundingBox, bb2: BoundingBox) !void {
    try testing.expectEqual(expectation, bb1.intersects(bb2));
    try testing.expectEqual(expectation, bb2.intersects(bb1));
}

fn expectContains(expectation: bool, bb: BoundingBox, point: Point) !void {
    try testing.expectEqual(expectation, bb.contains(point));
}

test "centeredOn creates correct bounding box" {
    const bb = BoundingBox.centeredOn(.{ .x = 80, .y = 40 }, 320, 200);

    try testing.expectEqual(-80, bb.x.min);
    try testing.expectEqual(-60, bb.y.min);
    try testing.expectEqual(240, bb.x.max);
    try testing.expectEqual(140, bb.y.max);
}

test "centeredOn creates corrected bounding box for odd values" {
    const bb = BoundingBox.centeredOn(.{ .x = 80, .y = 40 }, 201, 99);

    try testing.expectEqual(-20, bb.x.min);
    try testing.expectEqual(181, bb.x.max);
    try testing.expectEqual(-9, bb.y.min);
    try testing.expectEqual(90, bb.y.max);
}

test "centeredOn handles max dimensions without trapping" {
    const max = math.maxInt(BoundingBox.Dimension);
    const bb = BoundingBox.centeredOn(.{ .x = 0, .y = 0 }, max, max);

    // This is a pathological edge case caused by applying the division remainder
    // from an uneven width/height to the max instead of the min, causing the max to overflow.
    // Solving this would require either clamping the dimensions or diverging even further
    // from the original game's rounding behaviour; we can assume that the original implementation
    // never intended or needed to account for max dimensions, so I'm leaving this unfixed for now.
    try testing.expectEqual(-32767, bb.x.min);
    try testing.expectEqual(-32768, bb.x.max);
    try testing.expectEqual(-32767, bb.y.min);
    try testing.expectEqual(-32768, bb.y.max);
}

test "centeredOn overflows without trapping" {
    const max = math.maxInt(Point.Coordinate);
    const bb = BoundingBox.centeredOn(.{ .x = max, .y = max }, 2, 2);

    try testing.expectEqual(32766, bb.x.min);
    try testing.expectEqual(-32768, bb.x.max);
    try testing.expectEqual(32766, bb.y.min);
    try testing.expectEqual(-32768, bb.y.max);
}

test "centeredOn underflows without trapping" {
    const min = math.minInt(Point.Coordinate);
    const bb = BoundingBox.centeredOn(.{ .x = min, .y = min }, 2, 2);

    try testing.expectEqual(32767, bb.x.min);
    try testing.expectEqual(-32767, bb.x.max);
    try testing.expectEqual(32767, bb.y.min);
    try testing.expectEqual(-32767, bb.y.max);
}

test "origin returns expected origin" {
    const bb = BoundingBox{
        .x = .{ .min = 160, .max = 320 },
        .y = .{ .min = 100, .max = 200 },
    };
    try testing.expectEqual(.{ .x = 160, .y = 100 }, bb.origin());
}

test "intersects returns true for overlapping rectangles" {
    const reference = BoundingBox.init(0, 0, 319, 199);

    const touching_top_left = BoundingBox.init(-4, -4, 0, 0);
    const touching_bottom_right = BoundingBox.init(319, 199, 320, 200);

    const touching_left_edge = BoundingBox.init(-4, 0, 0, 199);
    const touching_right_edge = BoundingBox.init(319, 0, 324, 199);
    const touching_top_edge = BoundingBox.init(0, -4, 319, 0);
    const touching_bottom_edge = BoundingBox.init(0, 199, 319, 204);

    const completely_enclosed = BoundingBox.init(160, 100, 200, 120);
    const completely_encloses = BoundingBox.init(-200, -200, 400, 400);

    try expectIntersects(true, reference, touching_top_left);
    try expectIntersects(true, reference, touching_bottom_right);
    try expectIntersects(true, reference, touching_left_edge);
    try expectIntersects(true, reference, touching_right_edge);
    try expectIntersects(true, reference, touching_top_edge);
    try expectIntersects(true, reference, touching_bottom_edge);
    try expectIntersects(true, reference, completely_enclosed);
    try expectIntersects(true, reference, completely_encloses);
}

test "encloses returns true for completely enclosed rectangles and false for others" {
    const reference = BoundingBox.init(0, 0, 319, 199);

    const completely_enclosed = BoundingBox.init(160, 100, 200, 120);
    const equal = reference;

    const overlapping = BoundingBox.init(-4, 4, 240, 10);
    const completely_encloses = BoundingBox.init(-200, -200, 400, 400);
    const completely_disjoint = BoundingBox.init(-5000, -5000, -4000, -4000);

    try testing.expectEqual(true, reference.encloses(completely_enclosed));
    try testing.expectEqual(true, reference.encloses(equal));

    try testing.expectEqual(false, reference.encloses(overlapping));
    try testing.expectEqual(false, reference.encloses(completely_disjoint));
    try testing.expectEqual(false, reference.encloses(completely_encloses));
}

test "intersects returns false for disjoint rectangles" {
    const reference = BoundingBox.init(0, 0, 319, 199);

    const not_quite_touching_top_left = BoundingBox.init(-4, -4, -1, -1);
    const not_quite_touching_bottom_left = BoundingBox.init(320, 200, 324, 204);

    const not_quite_touching_left_edge = BoundingBox.init(-4, 0, -1, 199);
    const not_quite_touching_right_edge = BoundingBox.init(320, 0, 324, 199);
    const not_quite_touching_top_edge = BoundingBox.init(0, -4, 319, -1);
    const not_quite_touching_bottom_edge = BoundingBox.init(0, 200, 319, 204);

    const completely_disjoint = BoundingBox.init(-5000, -5000, -4000, -4000);

    try expectIntersects(false, reference, not_quite_touching_top_left);
    try expectIntersects(false, reference, not_quite_touching_bottom_left);
    try expectIntersects(false, reference, not_quite_touching_left_edge);
    try expectIntersects(false, reference, not_quite_touching_right_edge);
    try expectIntersects(false, reference, not_quite_touching_top_edge);
    try expectIntersects(false, reference, not_quite_touching_bottom_edge);
    try expectIntersects(false, reference, completely_disjoint);
}

test "contains returns true for points within bounds" {
    const reference = BoundingBox.init(0, 0, 319, 199);

    const top_left_corner = Point{ .x = 0, .y = 0 };
    const bottom_right_corner = Point{ .x = 319, .y = 199 };
    const left_edge = Point{ .x = 0, .y = 100 };
    const right_edge = Point{ .x = 319, .y = 100 };
    const top_edge = Point{ .x = 160, .y = 0 };
    const bottom_edge = Point{ .x = 160, .y = 199 };
    const center = Point{ .x = 160, .y = 100 };

    try expectContains(true, reference, top_left_corner);
    try expectContains(true, reference, bottom_right_corner);
    try expectContains(true, reference, left_edge);
    try expectContains(true, reference, right_edge);
    try expectContains(true, reference, top_edge);
    try expectContains(true, reference, bottom_edge);
    try expectContains(true, reference, center);
}

test "contains returns false for points out of bounds" {
    const reference = BoundingBox.init(0, 0, 319, 199);

    const not_quite_top_left_corner = Point{ .x = -1, .y = -1 };
    const not_quite_bottom_rightcorner = Point{ .x = 320, .y = 200 };
    const not_quite_left_edge = Point{ .x = -1, .y = 100 };
    const not_quite_right_edge = Point{ .x = 320, .y = 100 };
    const not_quite_top_edge = Point{ .x = 160, .y = -1 };
    const not_quite_bottom_edge = Point{ .x = 160, .y = 200 };
    const somewhere_else_entirely = Point{ .x = -5000, .y = -5000 };

    try expectContains(false, reference, not_quite_top_left_corner);
    try expectContains(false, reference, not_quite_bottom_rightcorner);
    try expectContains(false, reference, not_quite_left_edge);
    try expectContains(false, reference, not_quite_right_edge);
    try expectContains(false, reference, not_quite_top_edge);
    try expectContains(false, reference, not_quite_bottom_edge);
    try expectContains(false, reference, somewhere_else_entirely);
}

test "isUnit returns true for 0-width, 1-height bounding box" {
    const bb = BoundingBox.init(160, 100, 160, 101);
    try testing.expectEqual(true, bb.isUnit());
}

test "isUnit returns false for 1-width, 1-height bounding box" {
    const bb = BoundingBox.init(160, 100, 161, 101);
    try testing.expectEqual(false, bb.isUnit());
}

test "isUnit returns false for 0-width, 0-height bounding box" {
    const bb = BoundingBox.init(160, 100, 160, 100);
    try testing.expectEqual(false, bb.isUnit());
}
