const anotherworld = @import("../anotherworld.zig");

const Polygon = @import("polygon.zig").Polygon;
const ColorID = @import("color_id.zig").ColorID;
const Point = @import("point.zig").Point;
const Range = @import("range.zig").Range;
const FixedPrecision = @import("fixed_precision.zig").FixedPrecision;

const static_limits = anotherworld.static_limits;
const math = @import("std").math;

/// Draws a single polygon into a buffer using the position and draw mode specified in the polygon's data.
/// Returns an error if:
/// - the polygon contains < 4 vertices.
/// - any vertex along the right-hand side of the polygon is higher than the previous vertex.
/// - any vertex along the right-hand side of the polygon is > 1023 units below the previous vertex.
pub fn drawPolygon(comptime Buffer: type, buffer: *Buffer, mask_buffer: *const Buffer, polygon: Polygon) Error!void {
    const operation = Buffer.DrawOperation.forMode(polygon.draw_mode, mask_buffer);

    // Early-out for polygons that cover a single screen pixel
    if (polygon.isDot()) {
        const origin = polygon.bounds.origin();
        // Skip if the dot is offscreen
        if (Buffer.bounds.contains(origin)) {
            buffer.uncheckedDrawDot(origin, operation);
        }
        return;
    }

    // Skip if none of the polygon is on-screen
    if (Buffer.bounds.intersects(polygon.bounds) == false) {
        return;
    }

    const vertices = polygon.vertices();
    // Correctness check: we need at least 4 vertices to draw anything.
    // Invalid polygons would have been caught earlier when parsing,
    // but this method cannot prove that it hasn't received one.
    if (vertices.len < Polygon.min_vertices) return error.VertexCountTooLow;

    // Another World polygons are stored as lists of vertices clockwise from the top
    // of the polygon back up to the top. Each vertex is vertically aligned with a pair
    // at the other end of the vertex list.
    // To render the polygon, we walk the list of vertices from the start (clockwise)
    // and end (counterclockwise), pairing up the vertices and forming a trapezoid
    // out of the edges between each pair of vertices and the pair before them.
    var cw_vertex: usize = 0;
    var ccw_vertex: usize = vertices.len - 1;

    // 16.16 fixed-point math ahoy!
    // The reference implementation tracked the X coordinates of the polygon as 32-bit values:
    // the top 16 bits are the whole coordinates, and the bottom 16 bits are the fractional
    // components of each, which accumulate and roll over into the whole coordinate
    // as the routine traverses the edges of the polygon.
    //
    // (We could rewrite all of this to use floating-point math instead but where's the fun in that?)
    var x1 = FixedPrecision.init(vertices[cw_vertex].x);
    var x2 = FixedPrecision.init(vertices[ccw_vertex].x);
    var y = vertices[cw_vertex].y;

    cw_vertex += 1;
    ccw_vertex -= 1;

    // Walk through each pair of vertices, drawing spans of pixels between them.
    while (cw_vertex < ccw_vertex) {
        // When calculating X offsets for this pair of edges, carry over the whole-number X coordinates
        // from the previous edges but wipe out any accumulated fractions.
        // DOCUMENT ME: What's up with these magic numbers for the fraction?
        // Why aren't they the same for each?
        x1.setFraction(0x8000);
        x2.setFraction(0x7FFF);

        // For each pair of edges, determine the number of rows to draw,
        // and calculate the slope of each edge as a step value representing
        // how much to change X between each row.
        const x1_delta = vertices[cw_vertex].x - vertices[cw_vertex - 1].x;
        const x2_delta = vertices[ccw_vertex].x - vertices[ccw_vertex + 1].x;
        const y_delta = math.cast(TrustedVerticalDelta, vertices[cw_vertex].y - vertices[cw_vertex - 1].y) catch {
            return error.InvalidVerticalDelta;
        };

        const x1_step = stepDistance(x1_delta, y_delta);
        const x2_step = stepDistance(x2_delta, y_delta);

        // If there's a vertical change between vertices,
        // draw a horizontal span for each unit of vertical difference.
        if (y_delta > 0) {
            var rows_remaining = y_delta;
            while (rows_remaining > 0) : (rows_remaining -= 1) {
                // Don't draw parts of the polygon that are outside the buffer,
                // but still accumulate their changes to x.
                if (Buffer.bounds.y.contains(y)) {
                    const x_range = Range(Point.Coordinate).init(x1.whole(), x2.whole());

                    // Only draw the row if the resulting span is within the buffer's bounds.
                    if (Buffer.bounds.x.intersection(x_range)) |clamped_range| {
                        buffer.uncheckedDrawSpan(clamped_range, y, operation);
                    }
                }

                y += 1;

                // Stop drawing immediately if we ever leave the bottom of the buffer.
                if (y > Buffer.bounds.y.max) return;

                // Otherwise, accumulate the step changes and move down to the next row.
                x1.add(x1_step);
                x2.add(x2_step);
            }
        } else {
            // If there has been no vertical change (i.e. the edges are horizontal), don't draw a span:
            // just accumulate any changes to the x offsets, which will apply to the next pair of edges.
            x1.add(x1_step);
            x2.add(x2_step);
        }

        cw_vertex += 1;
        ccw_vertex -= 1;
    }
}

/// The possible errors from a polygon render operation.
pub const Error = error{
    /// Attempted to draw a polygon with not enough vertices.
    VertexCountTooLow,
    /// Attempted to draw a polygon whose vertices were too far apart vertically.
    InvalidVerticalDelta,
};

// -- Precomputed slopes --

/// Delta y values in the polygon draw routine are cast to this type to enforce that they are within
/// the legal range for an index in the `precomputed_slopes` table.
const TrustedVerticalDelta = u10;

/// A lookup table of fixed-point x/y ratios for slopes of heights between 0 and `max_vertical_delta`.
/// The values in this table will be multiplied by the x component of a vector to calculate the x step
/// for each unit of y along the vector of {x,y}.
const precomputed_slopes = init: {
    var table: [static_limits.precomputed_slope_count]u16 = undefined;

    const base = 1 << 14;
    table[0] = base;
    var index: u16 = 1;

    @setEvalBranchQuota(table.len);
    while (index < table.len) : (index += 1) {
        table[index] = base / index;
    }

    break :init table;
};

/// Given an {x, y} vector, calculates the step to add to x for each unit of y
/// to draw a slope along that vector.
fn stepDistance(delta_x: Point.Coordinate, delta_y: TrustedVerticalDelta) FixedPrecision {
    const slope = precomputed_slopes[delta_y];

    return .{
        // The slope table uses 14 bits of precision for the fractional component.
        // The final result must then be left-shifted by 2 to arrive at the desired 16.16 precision.
        .raw = (@as(i32, delta_x) * @as(i32, slope)) << 2,
    };
}

// -- Tests --

const testing = @import("utils").testing;
const expectPixels = @import("test_helpers/buffer_test_suite.zig").expectPixels;

/// Given a function that takes a width and a height and returns a type that implements the buffer interface,
/// test drawPolygon against that buffer type.
fn runTests(comptime BufferFn: anytype) void {
    _ = struct {
        test "drawPolygon draws a single-unit square polygon as a dot" {
            const poly = Polygon.init(
                .{ .solid_color = ColorID.cast(0x1) },
                &.{
                    .{ .x = 1, .y = 1 },
                    .{ .x = 1, .y = 2 },
                    .{ .x = 1, .y = 2 },
                    .{ .x = 1, .y = 1 },
                },
            );
            try testing.expect(poly.isDot());

            const Buffer = BufferFn(4, 4);
            var buffer = Buffer{};
            var mask_buffer = Buffer{};

            buffer.fill(ColorID.cast(0x0));
            mask_buffer.fill(ColorID.cast(0xF));

            const expected =
                \\0000
                \\0100
                \\0000
                \\0000
            ;

            try drawPolygon(Buffer, &buffer, &mask_buffer, poly);
            try expectPixels(expected, buffer);
        }

        test "drawPolygon draws a many-sided polygon" {
            const poly = Polygon.init(
                .{ .solid_color = ColorID.cast(0x1) },
                &.{
                    .{ .x = 3, .y = 1 },
                    .{ .x = 4, .y = 2 },
                    .{ .x = 2, .y = 4 },
                    .{ .x = 1, .y = 4 },
                    .{ .x = 1, .y = 2 },
                    .{ .x = 2, .y = 1 },
                },
            );

            const Buffer = BufferFn(6, 6);
            var buffer = Buffer{};
            var mask_buffer = Buffer{};

            buffer.fill(ColorID.cast(0x0));
            mask_buffer.fill(ColorID.cast(0xF));

            const expected =
                \\000000
                \\001100
                \\011110
                \\011100
                \\000000
                \\000000
            ;

            try drawPolygon(Buffer, &buffer, &mask_buffer, poly);
            try expectPixels(expected, buffer);
        }

        test "drawPolygon does not draw offscreen dot" {
            // The bounding box for a "unit" polygon is overcounted by 1 vertically,
            // so it technically covers 2 pixels even though only one pixel is drawn.
            // the bounds for this polygon will place the top (drawn) pixel offscreen
            // while the bottom (undrawn) pixel is onscreen.
            // FIXME: this is a flaw in our bounds calculations, that should ideally
            // be corrected upstream in the polygon parsing code.
            const poly = Polygon.init(
                .{ .solid_color = ColorID.cast(0x1) },
                &.{
                    .{ .x = 1, .y = -1 },
                    .{ .x = 1, .y = 0 },
                    .{ .x = 1, .y = 0 },
                    .{ .x = 1, .y = -1 },
                },
            );

            try testing.expect(poly.isDot());

            const Buffer = BufferFn(4, 4);
            var buffer = Buffer{};
            var mask_buffer = Buffer{};

            buffer.fill(ColorID.cast(0x0));
            mask_buffer.fill(ColorID.cast(0xF));

            const expected =
                \\0000
                \\0000
                \\0000
                \\0000
            ;

            try drawPolygon(Buffer, &buffer, &mask_buffer, poly);
            try expectPixels(expected, buffer);
        }

        test "drawPolygon crops partially-offscreen polygon" {
            const poly = Polygon.init(
                .{ .solid_color = ColorID.cast(0x1) },
                &.{
                    .{ .x = 6, .y = -1 },
                    .{ .x = 7, .y = 0 },
                    .{ .x = 5, .y = 2 },
                    .{ .x = 4, .y = 2 },
                    .{ .x = 4, .y = 0 },
                    .{ .x = 5, .y = -1 },
                },
            );

            const Buffer = BufferFn(6, 6);
            var buffer = Buffer{};
            var mask_buffer = Buffer{};

            buffer.fill(ColorID.cast(0x0));
            mask_buffer.fill(ColorID.cast(0xF));

            const expected =
                \\000011
                \\000011
                \\000000
                \\000000
                \\000000
                \\000000
            ;

            try drawPolygon(Buffer, &buffer, &mask_buffer, poly);
            try expectPixels(expected, buffer);
        }

        test "drawPolygon with malformed bounds does not draw offscreen" {
            var poly = Polygon.init(
                .{ .solid_color = ColorID.cast(0x1) },
                &.{
                    .{ .x = 3, .y = 6 },
                    .{ .x = 4, .y = 7 },
                    .{ .x = 2, .y = 10 },
                    .{ .x = 1, .y = 10 },
                    .{ .x = 1, .y = 7 },
                    .{ .x = 2, .y = 6 },
                },
            );
            // The polygon's vertices are all off the bottom of the screen,
            // but the bounds puts it on-screen.
            poly.bounds.y.min = 0;

            const Buffer = BufferFn(6, 6);
            var buffer = Buffer{};
            var mask_buffer = Buffer{};

            buffer.fill(ColorID.cast(0x0));
            mask_buffer.fill(ColorID.cast(0xF));

            const expected =
                \\000000
                \\000000
                \\000000
                \\000000
                \\000000
                \\000000
            ;

            try drawPolygon(Buffer, &buffer, &mask_buffer, poly);
            try expectPixels(expected, buffer);
        }

        test "drawPolygon with too few vertices returns error.VertexCountTooLow" {
            const poly = Polygon.init(.highlight, &.{
                .{ .x = 3, .y = 0 },
                .{ .x = 4, .y = 1 },
                .{ .x = 2, .y = 2 },
            });

            const Buffer = BufferFn(6, 6);
            var buffer = Buffer{};
            var mask_buffer = Buffer{};

            try testing.expectError(error.VertexCountTooLow, drawPolygon(Buffer, &buffer, &mask_buffer, poly));
        }

        test "drawPolygon with vertices too far apart returns error.InvalidVertexDelta" {
            const poly = Polygon.init(.highlight, &.{
                .{ .x = 1, .y = 0 },
                .{ .x = 1, .y = 16384 },
                .{ .x = 0, .y = 16384 },
                .{ .x = 0, .y = 0 },
            });

            const Buffer = BufferFn(6, 6);
            var buffer = Buffer{};
            var mask_buffer = Buffer{};

            try testing.expectError(error.InvalidVerticalDelta, drawPolygon(Buffer, &buffer, &mask_buffer, poly));
        }

        test "drawPolygon with backtracked vertices returns error.InvalidVertexDelta" {
            const poly = Polygon.init(.highlight, &.{
                .{ .x = 1, .y = 0 },
                .{ .x = 1, .y = -1 },
                .{ .x = 0, .y = -1 },
                .{ .x = 0, .y = 0 },
            });

            const Buffer = BufferFn(6, 6);
            var buffer = Buffer{};
            var mask_buffer = Buffer{};

            try testing.expectError(error.InvalidVerticalDelta, drawPolygon(Buffer, &buffer, &mask_buffer, poly));
        }
    };
}

const AlignedBuffer = @import("aligned_buffer.zig").AlignedBuffer;
const PackedBuffer = @import("packed_buffer.zig").PackedBuffer;

test "Run tests with aligned buffer" {
    runTests(AlignedBuffer);
}

test "Run tests with packed buffer" {
    runTests(PackedBuffer);
}
