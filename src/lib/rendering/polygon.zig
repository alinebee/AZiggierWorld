//! Another World stored polygon shapes as lists of X,Y vertices going clockwise from the top right of the shape,
//! down the right edge and around to the top left.
//!
//! To simplify its drawing algorithm, Another World constrained polygons so that:
//!
//! - Polygons have always have an even number of vertices between 4 and 50;
//! - Going clockwise, each vertex is aligned horizontally with the same-numbered vertex going counterclockwise;
//! - After scaling, the Y coordinate of each vertex must be between 0-1023 units below the one preceding it.
//!
//! These constraints meant that a polygon can be drawn as a vertical sequence of horizontally aligned rhombuses:
//! where each rhombus is made up of two pairs of vertices, the top and bottom edges of each rhombus are aligned
//! to a row of pixels, and no rhombus is more than 1023 pixels tall.
//!
//! This allows drawing to be optimized as runs of horizontal pixels between two slopes: where the slopes
//! are precalculated and stored in a lookup table of 1023 possible values suitable for fixed-precision math.
//!
//! Another optimization was to draw polygons with 4 vertices that were 1 pixel tall and wide after scaling
//! as single-pixel dots.
//!
//! (See draw_polygon.zig for the draw algorithm.)

const anotherworld = @import("../anotherworld.zig");
const meta = @import("utils").meta;
const static_limits = anotherworld.static_limits;

const Point = @import("point.zig").Point;
const BoundingBox = @import("bounding_box.zig").BoundingBox;
const DrawMode = @import("draw_mode.zig").DrawMode;
const PolygonScale = @import("polygon_scale.zig").PolygonScale;

const math = @import("std").math;
const BoundedArray = @import("std").BoundedArray;

/// Defines a scaled polygon in screen space, with between 4 and 50 vertices.
pub const Polygon = struct {
    const VertexStorage = BoundedArray(Point, max_vertices);

    /// The draw mode with which to render this polygon.
    draw_mode: DrawMode,

    /// The scaled bounding box of this polygon in screen coordinates.
    bounds: BoundingBox,

    /// The vertices making up this polygon in screen coordinates.
    /// Access via `vertices` instead of directly.
    _raw_vertices: VertexStorage,

    const Self = @This();

    /// Construct a valid polygon instance with the specified vertices.
    /// Intended for testing purposes and does not make use of actual game data.
    /// Precondition: vertices must have > 0 and <= 50 entries.
    pub fn init(draw_mode: DrawMode, verts: []const Point) Self {
        var self = Self{
            .draw_mode = draw_mode,
            ._raw_vertices = VertexStorage.init(verts.len) catch unreachable,
            .bounds = undefined,
        };

        var min_x: ?Point.Coordinate = null;
        var min_y: ?Point.Coordinate = null;
        var max_x: ?Point.Coordinate = null;
        var max_y: ?Point.Coordinate = null;

        for (verts) |vertex, index| {
            self._raw_vertices.set(index, vertex);
            min_x = if (min_x) |current| math.min(current, vertex.x) else vertex.x;
            max_x = if (max_x) |current| math.max(current, vertex.x) else vertex.x;
            min_y = if (min_y) |current| math.min(current, vertex.y) else vertex.y;
            max_y = if (max_y) |current| math.max(current, vertex.y) else vertex.y;
        }

        self.bounds = BoundingBox.init(min_x.?, min_y.?, max_x.?, max_y.?);
        return self;
    }

    /// Parse a stream of bytes from an Another World polygon resource into a polygon instance,
    /// scaling and positioning it according to the specified center and scale factor.
    pub fn parse(reader: anytype, center: Point, scale: PolygonScale, draw_mode: DrawMode) ParseError(@TypeOf(reader))!Self {
        const raw_width = try reader.readByte();
        const raw_height = try reader.readByte();
        const count = try reader.readByte();

        if (count > max_vertices) {
            return error.VertexCountTooHigh;
        }

        const scaled_width = scale.apply(BoundingBox.Dimension, raw_width);
        const scaled_height = scale.apply(BoundingBox.Dimension, raw_height);
        const bounds = BoundingBox.centeredOn(center, scaled_width, scaled_height);

        var self = Self{
            .draw_mode = draw_mode,
            .bounds = bounds,
            ._raw_vertices = VertexStorage.init(count) catch unreachable,
        };

        const origin = bounds.origin();
        var index: usize = 0;
        while (index < count) : (index += 1) {
            const raw_x = try reader.readByte();
            const raw_y = try reader.readByte();

            self._raw_vertices.set(index, origin.adding(.{
                .x = scale.apply(Point.Coordinate, raw_x),
                .y = scale.apply(Point.Coordinate, raw_y),
            }));
        }

        return self;
    }

    /// Returns a bounds-checked slice of the vertices in this polygon.
    pub fn vertices(self: Self) []const Point {
        return self._raw_vertices.constSlice();
    }

    /// Whether this polygon represents a single-pixel dot.
    pub fn isDot(self: Self) bool {
        return self._raw_vertices.len == min_vertices and self.bounds.isUnit();
    }

    /// Validates that the polygon has a legal number of vertices and the expected
    /// relationship of vertical distances.
    /// Only used by tests; drawPolygon does a more restricted set of checks
    /// when rasterizing polygon data.
    pub fn validate(self: Self) ValidationError!void {
        // Polygons must contain an even number of vertices
        if (@rem(self._raw_vertices.len, 2) != 0) return error.VertexCountUneven;

        // Polygons must contain at least 4 and at most 50 vertices
        if (self._raw_vertices.len < min_vertices) return error.VertexCountTooLow;
        if (self._raw_vertices.len > max_vertices) return error.VertexCountTooHigh;

        const verts = self.vertices();

        var clockwise_index: usize = 0;
        var counterclockwise_index: usize = verts.len - 1;

        while (clockwise_index < counterclockwise_index) {
            const current_y = verts[clockwise_index].y;

            // Vertex pairs must be aligned horizontally.
            if (current_y != verts[counterclockwise_index].y) {
                return error.VerticesMisaligned;
            }

            if (clockwise_index > 0) {
                const previous_y = verts[clockwise_index - 1].y;
                const delta_y = current_y - previous_y;

                // Each vertex must always be below the previous one.
                if (delta_y < min_vertical_span) {
                    return error.VerticesBacktracked;
                }

                // No two vertices can be more than 1023 units vertically apart.
                if (delta_y > max_vertical_span) {
                    return error.VerticesTooFarApart;
                }
            }

            clockwise_index += 1;
            counterclockwise_index -= 1;
        }
    }

    // - Exported constants -

    pub const min_vertices = 4;
    const max_vertices = static_limits.max_polygon_vertices;
    const min_vertical_span = 0;
    const max_vertical_span = static_limits.precomputed_slope_count - 1;

    pub fn ParseError(comptime Reader: type) type {
        const ReaderError = meta.ErrorType(Reader.readByte);
        return ReaderError || error{
            VertexCountTooHigh,
        };
    }

    pub const ValidationError = error{
        /// The polygon specified an odd number of vertices.
        VertexCountUneven,
        /// The polygon contained too few vertices.
        VertexCountTooLow,
        /// The polygon contained too many vertices.
        VertexCountTooHigh,
        /// The polygon contained a vertex pair that was not aligned vertically.
        VerticesMisaligned,
        /// The vertical distance between two polygon vertices was too great.
        VerticesTooFarApart,
        /// A subsequent vertex was higher up than the one preceding it.
        VerticesBacktracked,
    };

    // -- Data examples --

    // zig fmt: off
    pub const Fixtures = struct {
        pub const valid_dot = [_]u8 {
            0, 1, // width and height
            4, // vertex count
            0, 0,
            0, 1,
            0, 1,
            0, 0,
        };

        const valid_pentagon = [_]u8 {
            10, 10,
            6,
            // Vertices are stored in clockwise order, starting and ending at the top.
            // Polygons always have an even number of vertices, and each vertex lines
            // up with its pair along a horizontal line.
            // For the points of a pentagon, that would look like:
            //         6|1
            //
            //    5           2
            //
            //
            //       4     3
            5, 0,  // 1
            10, 4, // 2
            7, 10, // 3
            3, 10, // 4
            0, 4,  // 5
            5, 0,  // 6
        };

        const vertex_count_too_low = [_]u8 { 0, 1, 2, 0, 0, 0, 0 };
        const vertex_count_too_high = [_]u8 { 0, 1, 52 };
        const vertex_count_uneven = [_]u8 {
            0, 1,
            5,
            0, 0,
            0, 0,
            0, 0,
            0, 0,
            0, 0,
        };

        const vertices_misaligned = [_]u8 {
            10, 10,
            4,
            10, 0,
            10, 10,
            0, 9,
            0, 0,
        };

        const vertices_backtracked = [_]u8 {
            10, 10,
            6,
            5, 0,
            10, 4,
            7, 2,
            3, 2,
            0, 4,
            5, 0,
        };

        // This must be scaled up by more than 4x to actually exceed the max vertical span.
        const vertices_too_far_apart = [_]u8 {
            10, 255,
            4,
            10, 0,
            10, 255,
            0, 255,
            0, 0,
        };
    };
    // zig fmt: on
};

// -- Tests --

const testing = @import("utils").testing;
const fixedBufferStream = @import("std").io.fixedBufferStream;

test "parse correctly parses 4-vertex dot polygon" {
    const reader = fixedBufferStream(&Polygon.Fixtures.valid_dot).reader();

    const center = Point{ .x = 320, .y = 200 };
    const polygon = try Polygon.parse(reader, center, .default, .highlight);

    try testing.expectEqual(320, polygon.bounds.x.min);
    try testing.expectEqual(200, polygon.bounds.y.min);
    try testing.expectEqual(320, polygon.bounds.x.max);
    try testing.expectEqual(201, polygon.bounds.y.max);

    const vertices = polygon.vertices();
    try testing.expectEqual(4, vertices.len);
    try testing.expectEqual(true, polygon.isDot());

    try testing.expectEqual(.{ .x = 320, .y = 200 }, vertices[0]);
    try testing.expectEqual(.{ .x = 320, .y = 201 }, vertices[1]);
    try testing.expectEqual(.{ .x = 320, .y = 201 }, vertices[2]);
    try testing.expectEqual(.{ .x = 320, .y = 200 }, vertices[3]);
}

// zig fmt: off
test "parse correctly parses and scales pentagon" {
    const reader = fixedBufferStream(&Polygon.Fixtures.valid_pentagon).reader();

    const center = Point.zero;
    const polygon = try Polygon.parse(reader, center, .double, .highlight);

    try testing.expectEqual(-10, polygon.bounds.x.min);
    try testing.expectEqual(-10, polygon.bounds.y.min);
    try testing.expectEqual(10, polygon.bounds.x.max);
    try testing.expectEqual(10, polygon.bounds.y.max);

    const vertices = polygon.vertices();
    try testing.expectEqual(6, vertices.len);
    try testing.expectEqual(false, polygon.isDot());

    try testing.expectEqual(.{ .x = 0,      .y = -10 }, vertices[0]);
    try testing.expectEqual(.{ .x = 10,     .y = -2 },  vertices[1]);
    try testing.expectEqual(.{ .x = 4,      .y = 10 },  vertices[2]);
    try testing.expectEqual(.{ .x = -4,     .y = 10 },  vertices[3]);
    try testing.expectEqual(.{ .x = -10,    .y = -2 },  vertices[4]);
    try testing.expectEqual(.{ .x = 0,      .y = -10 }, vertices[5]);
}
// zig fmt: on

test "parse returns error.VertexCountTooHigh when count is too high" {
    const reader = fixedBufferStream(&Polygon.Fixtures.vertex_count_too_high).reader();
    try testing.expectError(error.VertexCountTooHigh, Polygon.parse(reader, Point.zero, .default, .highlight));
}

test "validate returns error.VertexCountTooLow when count is too low" {
    const reader = fixedBufferStream(&Polygon.Fixtures.vertex_count_too_low).reader();
    const polygon = try Polygon.parse(reader, Point.zero, .default, .highlight);
    try testing.expectError(error.VertexCountTooLow, polygon.validate());
}

test "validate returns error.VertexCountUneven when count is uneven" {
    const reader = fixedBufferStream(&Polygon.Fixtures.vertex_count_uneven).reader();
    const polygon = try Polygon.parse(reader, Point.zero, .default, .highlight);
    try testing.expectError(error.VertexCountUneven, polygon.validate());
}

test "validate returns error.VerticesMisaligned when vertex pairs are not aligned horizontally" {
    const reader = fixedBufferStream(&Polygon.Fixtures.vertices_misaligned).reader();
    const polygon = try Polygon.parse(reader, Point.zero, .default, .highlight);
    try testing.expectError(error.VerticesMisaligned, polygon.validate());
}

test "validate returns error.VerticesBacktracked when a clockwise vertex is above the one before it" {
    const reader = fixedBufferStream(&Polygon.Fixtures.vertices_backtracked).reader();
    const polygon = try Polygon.parse(reader, Point.zero, .default, .highlight);
    try testing.expectError(error.VerticesBacktracked, polygon.validate());
}

test "validate returns error.VerticesTooFarApart when a clockwise vertex is more than 1023 units below the one before it" {
    const reader = fixedBufferStream(&Polygon.Fixtures.vertices_too_far_apart).reader();
    const polygon = try Polygon.parse(reader, Point.zero, PolygonScale.cast(258), .highlight);
    try testing.expectError(error.VerticesTooFarApart, polygon.validate());
}

test "new creates polygon with expected bounding box and vertices" {
    const vertices = [_]Point{
        .{ .x = 1, .y = 1 },
        .{ .x = 1, .y = 2 },
        .{ .x = 1, .y = 2 },
        .{ .x = 1, .y = 1 },
    };

    const polygon = Polygon.init(.mask, &vertices);

    try testing.expectEqual(.mask, polygon.draw_mode);
    try testing.expectEqual(4, polygon.vertices().len);
    try testing.expectEqualSlices(Point, &vertices, polygon.vertices());

    try testing.expectEqual(1, polygon.bounds.x.min);
    try testing.expectEqual(1, polygon.bounds.x.max);
    try testing.expectEqual(1, polygon.bounds.y.min);
    try testing.expectEqual(2, polygon.bounds.y.max);
    try testing.expect(polygon.bounds.isUnit());
}
