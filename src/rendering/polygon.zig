const Point = @import("../values/point.zig");
const PolygonDrawMode = @import("../values/polygon_draw_mode.zig");
const PolygonScale = @import("../values/polygon_scale.zig");
const BoundingBox = @import("../values/bounding_box.zig");

const introspection = @import("../utils/introspection.zig");

const min_vertices = 4;
const max_vertices = 50;

pub const Instance = struct {
    /// The draw mode with which to render this polygon.
    draw_mode: PolygonDrawMode.Enum,

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

pub fn parse(reader: anytype, center: Point.Instance, scale: PolygonScale.Raw, draw_mode: PolygonDrawMode.Enum) Error(@TypeOf(reader))!Instance {
    const scaled_width = PolygonScale.apply(BoundingBox.Dimension, try reader.readByte(), scale);
    const scaled_height = PolygonScale.apply(BoundingBox.Dimension, try reader.readByte(), scale);

    var self = Instance{
        .draw_mode = draw_mode,
        .bounds = BoundingBox.new(center, scaled_width, scaled_height),
        .count = try reader.readByte(),
        .vertices = undefined,
    };

    try validateVertexCount(self.count);

    var index: usize = 0;
    while (index < self.count) : (index += 1) {
        self.vertices[index] = .{
            // TODO: add tests for wrap-on-overflow
            .x = PolygonScale.apply(Point.Coordinate, try reader.readByte(), scale) +% self.bounds.minX,
            .y = PolygonScale.apply(Point.Coordinate, try reader.readByte(), scale) +% self.bounds.minY,
        };
    }

    return self;
}

fn validateVertexCount(count: usize) ValidationError!void {
    // Polygons must contain an even number of vertices
    if (@rem(count, 2) != 0) return error.InvalidVertexCount;

    // Polygons must contain at least 4 and at most 50 vertices
    if (count < min_vertices) return error.InvalidVertexCount;
    if (count > max_vertices) return error.InvalidVertexCount;

    // TODO: these are not the only constraints on vertices;
    // - vertices must start and end at the top;
    // - pairs of vertices must be aligned on the Y axis;
    // - pairs of vertices can be no more than 1024 units apart.
}

const ValidationError = error{
    /// The polygon definition specified an illegal number of vertices.
    InvalidVertexCount,
};

pub fn Error(comptime Reader: type) type {
    const ReadError = introspection.errorType(Reader.readByte);
    return ReadError || ValidationError;
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
};
// zig fmt: on

// -- Tests --

const testing = @import("../utils/testing.zig");
const fixedBufferStream = @import("std").io.fixedBufferStream;

test "parse correctly parses 4-vertex dot polygon" {
    var stream = fixedBufferStream(&DataExamples.valid_dot);
    const reader = stream.reader();

    const center = Point.Instance{ .x = 320, .y = 200 };
    const polygon = try parse(reader, center, PolygonScale.default, .translucent);

    testing.expectEqual(320, polygon.bounds.minX);
    testing.expectEqual(200, polygon.bounds.minY);
    testing.expectEqual(320, polygon.bounds.maxX);
    testing.expectEqual(201, polygon.bounds.maxY);

    testing.expectEqual(4, polygon.count);
    testing.expectEqual(true, polygon.isDot());

    testing.expectEqual(.{ .x = 320, .y = 200 }, polygon.vertices[0]);
    testing.expectEqual(.{ .x = 320, .y = 201 }, polygon.vertices[1]);
    testing.expectEqual(.{ .x = 320, .y = 201 }, polygon.vertices[2]);
    testing.expectEqual(.{ .x = 320, .y = 200 }, polygon.vertices[3]);
}

// zig fmt: off
test "parse correctly parses and scales pentagon" {
    var stream = fixedBufferStream(&DataExamples.valid_pentagon);
    const reader = stream.reader();

    const center = Point.Instance{ .x = 0, .y = 0 };
    const polygon = try parse(reader, center, PolygonScale.default * 2, .translucent);

    testing.expectEqual(-10, polygon.bounds.minX);
    testing.expectEqual(-10, polygon.bounds.minY);
    testing.expectEqual(10, polygon.bounds.maxX);
    testing.expectEqual(10, polygon.bounds.maxY);

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
