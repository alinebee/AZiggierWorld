const Point = @import("../values/point.zig");
const DrawMode = @import("../values/draw_mode.zig");
const PolygonScale = @import("../values/polygon_scale.zig");
const BoundingBox = @import("../values/bounding_box.zig");

const introspection = @import("../utils/introspection.zig");

/// Defines a scaled polygon in screen space, with between 4 and 50 polygons.
pub const Instance = struct {
    /// The draw mode with which to render this polygon.
    draw_mode: DrawMode.Enum,

    /// The scaled bounding box of this polygon in screen coordinates.
    bounds: BoundingBox.Instance,

    /// The number of vertices in this polygon.
    count: usize,

    /// The vertices making up this polygon in screen coordinates.
    /// Only the first `count` entries contain valid data.
    /// Usage: polygon.vertices[0..polygon.count]
    vertices: [max_vertices]Point.Instance,

    /// Whether this polygon represents a single-pixel dot.
    pub fn isDot(self: Instance) bool {
        return self.count == min_vertices and self.bounds.isUnit();
    }
};

pub fn parse(reader: anytype, center: Point.Instance, scale: PolygonScale.Raw, draw_mode: DrawMode.Enum) Error(@TypeOf(reader))!Instance {
    const scaled_width = PolygonScale.apply(BoundingBox.Dimension, try reader.readByte(), scale);
    const scaled_height = PolygonScale.apply(BoundingBox.Dimension, try reader.readByte(), scale);

    var self = Instance{
        .draw_mode = draw_mode,
        .bounds = BoundingBox.centeredOn(center, scaled_width, scaled_height),
        .count = try reader.readByte(),
        .vertices = undefined,
    };

    try validateVertexCount(self.count);

    var index: usize = 0;
    while (index < self.count) : (index += 1) {
        self.vertices[index] = .{
            // TODO: add tests for wrap-on-overflow
            .x = PolygonScale.apply(Point.Coordinate, try reader.readByte(), scale) +% self.bounds.x.min,
            .y = PolygonScale.apply(Point.Coordinate, try reader.readByte(), scale) +% self.bounds.y.min,
        };
    }

    try validateVertices(self.vertices[0..self.count]);

    return self;
}

/// The errors that can be returned by a call to `parse`.
pub fn Error(comptime Reader: type) type {
    const ReadError = introspection.errorType(Reader.readByte);
    return ReadError || ValidationError;
}

const min_vertices = 4;
const max_vertices = 50;

const min_vertical_span = 0;
const max_vertical_span = 1023;

const ValidationError = error{
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

/// Validate that the vertex count of a polygon definition is correct.
fn validateVertexCount(count: usize) ValidationError!void {
    // Polygons must contain an even number of vertices
    if (@rem(count, 2) != 0) return error.VertexCountUneven;

    // Polygons must contain at least 4 and at most 50 vertices
    if (count < min_vertices) return error.VertexCountTooLow;
    if (count > max_vertices) return error.VertexCountTooHigh;
}

/// Validate that the relationships between vertices in a polygon definition are correct.
fn validateVertices(vertices: []const Point.Instance) ValidationError!void {
    var clockwise_index: usize = 0;
    var counterclockwise_index: usize = vertices.len - 1;

    while (clockwise_index < counterclockwise_index) {
        const current_y = vertices[clockwise_index].y;

        // Vertex pairs must be aligned horizontally.
        if (current_y != vertices[counterclockwise_index].y) {
            return error.VerticesMisaligned;
        }

        if (clockwise_index > 0) {
            const previous_y = vertices[clockwise_index - 1].y;
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

// -- Data examples --

// zig fmt: off
const DataExamples = struct {
    const valid_dot = [_]u8 {
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

    const vertex_count_too_low = [_]u8 { 0, 1, 2 };
    const vertex_count_too_high = [_]u8 { 0, 1, 52 };
    const vertex_count_uneven = [_]u8 { 0, 1, 5 };

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

// -- Tests --

const testing = @import("../utils/testing.zig");
const fixedBufferStream = @import("std").io.fixedBufferStream;

test "parse correctly parses 4-vertex dot polygon" {
    const reader = fixedBufferStream(&DataExamples.valid_dot).reader();

    const center = Point.Instance{ .x = 320, .y = 200 };
    const polygon = try parse(reader, center, PolygonScale.default, .highlight);

    testing.expectEqual(320, polygon.bounds.x.min);
    testing.expectEqual(200, polygon.bounds.y.min);
    testing.expectEqual(320, polygon.bounds.x.max);
    testing.expectEqual(201, polygon.bounds.y.max);

    testing.expectEqual(4, polygon.count);
    testing.expectEqual(true, polygon.isDot());

    testing.expectEqual(.{ .x = 320, .y = 200 }, polygon.vertices[0]);
    testing.expectEqual(.{ .x = 320, .y = 201 }, polygon.vertices[1]);
    testing.expectEqual(.{ .x = 320, .y = 201 }, polygon.vertices[2]);
    testing.expectEqual(.{ .x = 320, .y = 200 }, polygon.vertices[3]);
}

// zig fmt: off
test "parse correctly parses and scales pentagon" {
    const reader = fixedBufferStream(&DataExamples.valid_pentagon).reader();

    const center = Point.zero;
    const polygon = try parse(reader, center, PolygonScale.default * 2, .highlight);

    testing.expectEqual(-10, polygon.bounds.x.min);
    testing.expectEqual(-10, polygon.bounds.y.min);
    testing.expectEqual(10, polygon.bounds.x.max);
    testing.expectEqual(10, polygon.bounds.y.max);

    testing.expectEqual(6, polygon.count);
    testing.expectEqual(false, polygon.isDot());

    testing.expectEqual(.{ .x = 0,      .y = -10 }, polygon.vertices[0]);
    testing.expectEqual(.{ .x = 10,     .y = -2 },  polygon.vertices[1]);
    testing.expectEqual(.{ .x = 4,      .y = 10 },  polygon.vertices[2]);
    testing.expectEqual(.{ .x = -4,     .y = 10 },  polygon.vertices[3]);
    testing.expectEqual(.{ .x = -10,    .y = -2 },  polygon.vertices[4]);
    testing.expectEqual(.{ .x = 0,      .y = -10 }, polygon.vertices[5]);
}
// zig fmt: on

test "parse returns error.VertexCountTooLow when count is too low" {
    const reader = fixedBufferStream(&DataExamples.vertex_count_too_low).reader();
    testing.expectError(
        error.VertexCountTooLow,
        parse(reader, Point.zero, PolygonScale.default, .highlight),
    );
}

test "parse returns error.VertexCountTooHigh when count is too high" {
    const reader = fixedBufferStream(&DataExamples.vertex_count_too_high).reader();
    testing.expectError(
        error.VertexCountTooHigh,
        parse(reader, Point.zero, PolygonScale.default, .highlight),
    );
}

test "parse returns error.VertexCountUneven when count is uneven" {
    const reader = fixedBufferStream(&DataExamples.vertex_count_uneven).reader();
    testing.expectError(error.VertexCountUneven, parse(reader, Point.zero, PolygonScale.default, .highlight));
}

test "parse returns error.VerticesMisaligned when vertex pairs are not aligned horizontally" {
    const reader = fixedBufferStream(&DataExamples.vertices_misaligned).reader();
    testing.expectError(
        error.VerticesMisaligned,
        parse(reader, Point.zero, PolygonScale.default, .highlight),
    );
}

test "parse returns error.VerticesBacktracked when a clockwise vertex is above the one before it" {
    const reader = fixedBufferStream(&DataExamples.vertices_backtracked).reader();
    testing.expectError(
        error.VerticesBacktracked,
        parse(reader, Point.zero, PolygonScale.default, .highlight),
    );
}

test "parse returns error.VerticesTooFarApart when a clockwise vertex is more than 1023 units below the one before it" {
    const reader = fixedBufferStream(&DataExamples.vertices_too_far_apart).reader();
    testing.expectError(
        error.VerticesTooFarApart,
        parse(reader, Point.zero, 258, .highlight),
    );
}
