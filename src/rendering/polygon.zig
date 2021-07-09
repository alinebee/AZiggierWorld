const Point = @import("../values/point.zig");
const DrawMode = @import("../values/draw_mode.zig");
const PolygonScale = @import("../values/polygon_scale.zig");
const BoundingBox = @import("../values/bounding_box.zig");

const introspection = @import("../utils/introspection.zig");
const math = @import("std").math;

/// Defines a scaled polygon in screen space, with between 4 and 50 vertices.
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

/// Construct a valid polygon instance with the specified vertices.
/// Intended for testing purposes and does not make use of actual game data.
/// Precondition: vertices must have > 0 and <= 50 entries.
pub fn new(draw_mode: DrawMode.Enum, vertices: []const Point.Instance) Instance {
    if (vertices.len < min_vertices) @panic("Not enough vertices!");
    if (vertices.len > max_vertices) @panic("Too many vertices!");

    var self = Instance{
        .draw_mode = draw_mode,
        .count = vertices.len,
        .vertices = undefined,
        .bounds = undefined,
    };

    var min_x: ?Point.Coordinate = null;
    var min_y: ?Point.Coordinate = null;
    var max_x: ?Point.Coordinate = null;
    var max_y: ?Point.Coordinate = null;

    for (vertices) |vertex, index| {
        self.vertices[index] = vertex;
        min_x = if (min_x) |current| math.min(current, vertex.x) else vertex.x;
        max_x = if (max_x) |current| math.max(current, vertex.x) else vertex.x;
        min_y = if (min_y) |current| math.min(current, vertex.y) else vertex.y;
        max_y = if (max_y) |current| math.max(current, vertex.y) else vertex.y;
    }

    self.bounds = BoundingBox.new(min_x.?, min_y.?, max_x.?, max_y.?);
    return self;
}

/// Parse a stream of bytes from an Another World polygon resource into a polygon instance,
/// scaling and positioning it according to the specified center and scale factor.
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
    const ReadError = introspection.ErrorType(Reader.readByte);
    return ReadError || ValidationError;
}

pub const min_vertices = 4;
pub const max_vertices = 50;

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
pub const DataExamples = struct {
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

    try testing.expectEqual(320, polygon.bounds.x.min);
    try testing.expectEqual(200, polygon.bounds.y.min);
    try testing.expectEqual(320, polygon.bounds.x.max);
    try testing.expectEqual(201, polygon.bounds.y.max);

    try testing.expectEqual(4, polygon.count);
    try testing.expectEqual(true, polygon.isDot());

    try testing.expectEqual(.{ .x = 320, .y = 200 }, polygon.vertices[0]);
    try testing.expectEqual(.{ .x = 320, .y = 201 }, polygon.vertices[1]);
    try testing.expectEqual(.{ .x = 320, .y = 201 }, polygon.vertices[2]);
    try testing.expectEqual(.{ .x = 320, .y = 200 }, polygon.vertices[3]);
}

// zig fmt: off
test "parse correctly parses and scales pentagon" {
    const reader = fixedBufferStream(&DataExamples.valid_pentagon).reader();

    const center = Point.zero;
    const polygon = try parse(reader, center, PolygonScale.default * 2, .highlight);

    try testing.expectEqual(-10, polygon.bounds.x.min);
    try testing.expectEqual(-10, polygon.bounds.y.min);
    try testing.expectEqual(10, polygon.bounds.x.max);
    try testing.expectEqual(10, polygon.bounds.y.max);

    try testing.expectEqual(6, polygon.count);
    try testing.expectEqual(false, polygon.isDot());

    try testing.expectEqual(.{ .x = 0,      .y = -10 }, polygon.vertices[0]);
    try testing.expectEqual(.{ .x = 10,     .y = -2 },  polygon.vertices[1]);
    try testing.expectEqual(.{ .x = 4,      .y = 10 },  polygon.vertices[2]);
    try testing.expectEqual(.{ .x = -4,     .y = 10 },  polygon.vertices[3]);
    try testing.expectEqual(.{ .x = -10,    .y = -2 },  polygon.vertices[4]);
    try testing.expectEqual(.{ .x = 0,      .y = -10 }, polygon.vertices[5]);
}
// zig fmt: on

test "parse returns error.VertexCountTooLow when count is too low" {
    const reader = fixedBufferStream(&DataExamples.vertex_count_too_low).reader();
    try testing.expectError(
        error.VertexCountTooLow,
        parse(reader, Point.zero, PolygonScale.default, .highlight),
    );
}

test "parse returns error.VertexCountTooHigh when count is too high" {
    const reader = fixedBufferStream(&DataExamples.vertex_count_too_high).reader();
    try testing.expectError(
        error.VertexCountTooHigh,
        parse(reader, Point.zero, PolygonScale.default, .highlight),
    );
}

test "parse returns error.VertexCountUneven when count is uneven" {
    const reader = fixedBufferStream(&DataExamples.vertex_count_uneven).reader();
    try testing.expectError(error.VertexCountUneven, parse(reader, Point.zero, PolygonScale.default, .highlight));
}

test "parse returns error.VerticesMisaligned when vertex pairs are not aligned horizontally" {
    const reader = fixedBufferStream(&DataExamples.vertices_misaligned).reader();
    try testing.expectError(
        error.VerticesMisaligned,
        parse(reader, Point.zero, PolygonScale.default, .highlight),
    );
}

test "parse returns error.VerticesBacktracked when a clockwise vertex is above the one before it" {
    const reader = fixedBufferStream(&DataExamples.vertices_backtracked).reader();
    try testing.expectError(
        error.VerticesBacktracked,
        parse(reader, Point.zero, PolygonScale.default, .highlight),
    );
}

test "parse returns error.VerticesTooFarApart when a clockwise vertex is more than 1023 units below the one before it" {
    const reader = fixedBufferStream(&DataExamples.vertices_too_far_apart).reader();
    try testing.expectError(
        error.VerticesTooFarApart,
        parse(reader, Point.zero, 258, .highlight),
    );
}

test "new creates polygon with expected bounding box and vertices" {
    const vertices = [_]Point.Instance{
        .{ .x = 1, .y = 1 },
        .{ .x = 1, .y = 2 },
        .{ .x = 1, .y = 2 },
        .{ .x = 1, .y = 1 },
    };

    const polygon = new(.mask, &vertices);

    try testing.expectEqual(.mask, polygon.draw_mode);
    try testing.expectEqual(4, polygon.count);
    try testing.expectEqualSlices(Point.Instance, &vertices, polygon.vertices[0..4]);

    try testing.expectEqual(1, polygon.bounds.x.min);
    try testing.expectEqual(1, polygon.bounds.x.max);
    try testing.expectEqual(1, polygon.bounds.y.min);
    try testing.expectEqual(2, polygon.bounds.y.max);
    try testing.expect(polygon.bounds.isUnit());
}
