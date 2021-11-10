//! Another World uses 320x200-pixel video buffers, where each pixel is a 16-bit color index
//! in the current palette.
//!
//! The type defined in this file represents a 16-color buffer with arbitrary width and height.
//! It implements high-level draw operations to render polygons and text, but abstracts away
//! the storage of pixels to an encapsulated backing storage type, and defers pixel-level read
//! and write operations to that type.
//!
//! See packed_storage.zig and aligned_storage.zig for two storage implementations.

const ColorID = @import("../values/color_id.zig");
const Point = @import("../values/point.zig");
const Range = @import("../values/range.zig");
const BoundingBox = @import("../values/bounding_box.zig");
const FixedPrecision = @import("../values/fixed_precision.zig");
const DrawMode = @import("../values/draw_mode.zig");
const Font = @import("../assets/font.zig");
const Polygon = @import("polygon.zig");

const math = @import("std").math;

/// Creates a new video buffer with a given width and height, using the specified type as its backing storage.
pub fn new(comptime Storage: anytype, comptime width: usize, comptime height: usize) Instance(Storage, width, height) {
    return .{};
}

pub fn Instance(comptime StorageFn: anytype, comptime width: usize, comptime height: usize) type {
    const Storage = StorageFn(width, height);
    return struct {
        /// The backing storage for this video buffer, responsible for low-level pixel operations.
        storage: Storage = .{},

        /// The bounding box that encompasses all legal points within this buffer.
        pub const bounds = BoundingBox.new(0, 0, width - 1, height - 1);

        const Self = @This();

        /// Fill every pixel in the buffer with the specified color.
        pub fn fill(self: *Self, color: ColorID.Trusted) void {
            self.storage.fill(color);
        }

        /// Copy the contents of another buffer into this one at the specified Y offset.
        pub fn copy(self: *Self, other: *const Self, y: Point.Coordinate) void {
            self.storage.copy(&other.storage, y);
        }

        /// Load the contents of an Another World bitmap resource into this buffer,
        /// replacing all existing pixels. Returns an error if the specified bitmap data
        /// was the wrong size for this buffer.
        pub fn loadBitmapResource(self: *Self, bitmap_data: []const u8) !void {
            try self.storage.loadBitmapResource(bitmap_data);
        }

        /// Draw a single or multiline string in the specified color,
        /// positioning the top left corner of the text at the specified origin point.
        /// Returns an error if the string contains unsupported characters
        /// or tried to draw characters offscreen.
        pub fn drawString(self: *Self, string: []const u8, color: ColorID.Trusted, origin: Point.Instance) !void {
            const operation = Storage.DrawOperation.solidColor(color);

            var cursor = origin;
            for (string) |char| {
                switch (char) {
                    '\n' => {
                        cursor.x = origin.x;
                        cursor.y += Font.glyph_height;
                    },
                    else => {
                        const glyph = try Font.glyph(char);
                        try self.drawGlyph(glyph, cursor, operation);
                        cursor.x += Font.glyph_width;
                    },
                }
            }
        }

        /// Draws the specified 8x8 glyph in a solid color, positioning its top left corner at the specified point.
        /// Returns error.GlyphOutOfBounds if the glyph's bounds do not lie fully inside the buffer.
        fn drawGlyph(self: *Self, glyph: Font.Glyph, origin: Point.Instance, operation: Storage.DrawOperation) Error!void {
            const glyph_bounds = BoundingBox.new(origin.x, origin.y, origin.x + Font.glyph_width, origin.y + Font.glyph_height);

            if (Self.bounds.encloses(glyph_bounds) == false) {
                return error.GlyphOutOfBounds;
            }

            var cursor = origin;

            // Walk through each row of the glyph drawing spans of lit pixels.
            for (glyph) |row| {
                var remaining_pixels = row;
                var span_start: Point.Coordinate = cursor.x;
                var span_width: Point.Coordinate = 0;

                // Stop drawing the line as soon as there are no more lit pixels in it.
                while (remaining_pixels != 0) {
                    const pixel_lit = (remaining_pixels & 0b1000_0000) != 0;
                    remaining_pixels <<= 1;

                    // Accumulate lit pixels into a single span for more efficient drawing.
                    if (pixel_lit == true) span_width += 1;

                    // If we reach an unlit pixel, or the last lit pixel of the row,
                    // draw the current span of lit pixels and start a new span.
                    if (pixel_lit == false or remaining_pixels == 0) {
                        if (span_width > 0) {
                            const span_end = span_start + span_width - 1;
                            self.storage.uncheckedDrawSpan(.{ .min = span_start, .max = span_end }, cursor.y, operation);

                            span_start += span_width;
                            span_width = 0;
                        }
                        span_start += 1;
                    }
                }

                // Once we've consumed all pixels in the row, move down to the next one.
                cursor.y += 1;
            }
        }

        /// Draws a single polygon into the buffer using the position and draw mode specified in the polygon's data.
        /// Returns an error if:
        /// - the polygon contains < 4 vertices.
        /// - any vertex along the right-hand side of the polygon is higher than the previous vertex.
        /// - any vertex along the right-hand side of the polygon is > 1023 units below the previous vertex.
        pub fn drawPolygon(self: *Self, polygon: Polygon.Instance, mask_buffer: *const Self) Error!void {
            // Skip if none of the polygon is on-screen
            if (Self.bounds.intersects(polygon.bounds) == false) {
                return;
            }

            const operation = Storage.DrawOperation.forMode(polygon.draw_mode, &mask_buffer.storage);

            // Early-out for polygons that cover a single screen pixel
            if (polygon.isDot()) {
                const origin = polygon.bounds.origin();
                self.storage.uncheckedDrawDot(origin, operation);
                return;
            }

            const vertices = polygon.vertices();
            // Sanity check: we need at least 4 vertices to draw anything.
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
            var x1 = FixedPrecision.new(vertices[cw_vertex].x);
            var x2 = FixedPrecision.new(vertices[ccw_vertex].x);
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
                        if (Self.bounds.y.contains(y)) {
                            const x_range = Range.new(Point.Coordinate, x1.whole(), x2.whole());

                            // Only draw the row if the resulting span is within the buffer's bounds.
                            if (Self.bounds.x.intersection(x_range)) |clamped_range| {
                                self.storage.uncheckedDrawSpan(clamped_range, y, operation);
                            }
                        }

                        y += 1;

                        // Stop drawing immediately if we ever leave the bottom of the buffer.
                        if (y > Self.bounds.y.max) return;

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
    };
}

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
fn stepDistance(delta_x: Point.Coordinate, delta_y: TrustedVerticalDelta) FixedPrecision.Instance {
    const slope = precomputed_slopes[delta_y];

    return .{
        // The slope table uses 14 bits of precision for the fractional component.
        // The final result must then be left-shifted by 2 to arrive at the desired 16.16 precision.
        .raw = (@as(i32, delta_x) * @as(i32, slope)) << 2,
    };
}

/// The possible errors from buffer render operations.
pub const Error = error{
    /// Attempted to draw a glyph partially or entirely outside the buffer.
    GlyphOutOfBounds,
    /// Attempted to draw a polygon with not enough vertices.
    VertexCountTooLow,
    /// Attempted to draw a polygon whose vertices were too far apart vertically.
    InvalidVerticalDelta,
};

// -- Testing --

const testing = @import("../utils/testing.zig");
const expectPixels = @import("test_helpers/storage_test_suite.zig").expectPixels;

const AlignedStorage = @import("storage/aligned_storage.zig");
const PackedStorage = @import("storage/packed_storage.zig");
const PlanarBitmapResource = @import("../resources/planar_bitmap_resource.zig");

const static_limits = @import("../static_limits.zig");

test "TrustedVerticalDelta covers range of legal vertical deltas" {
    try static_limits.validateTrustedType(TrustedVerticalDelta, static_limits.precomputed_slope_count);
}

// -- Public draw method tests --

/// Test each method of the video buffer interface against an arbitrary storage type.
fn runTests(comptime Storage: anytype) void {
    _ = struct {
        test "Instance calculates expected bounding box" {
            const Buffer = @TypeOf(new(Storage, 320, 200));

            try testing.expectEqual(0, Buffer.bounds.x.min);
            try testing.expectEqual(0, Buffer.bounds.y.min);
            try testing.expectEqual(319, Buffer.bounds.x.max);
            try testing.expectEqual(199, Buffer.bounds.y.max);
        }

        test "fill fills buffer with specified color" {
            var buffer = new(Storage, 4, 4);
            buffer.storage.fillFromString(
                \\0123
                \\4567
                \\89AB
                \\CDEF
            );

            buffer.fill(0xF);

            const expected =
                \\FFFF
                \\FFFF
                \\FFFF
                \\FFFF
            ;

            try expectPixels(expected, buffer.storage);
        }

        test "copy copies contents of destination at specified offset" {
            var destination = new(Storage, 4, 4);
            destination.fill(0xF);

            var source = new(Storage, 4, 4);
            source.storage.fillFromString(
                \\0123
                \\4567
                \\89AB
                \\CDEF
            );

            destination.copy(&source, 2);

            const expected =
                \\FFFF
                \\FFFF
                \\0123
                \\4567
            ;

            try expectPixels(expected, destination.storage);
        }

        test "loadBitmapResource correctly parses planar bitmap data" {
            const data = &PlanarBitmapResource.DataExamples.valid_16px;

            var buffer = new(Storage, 4, 4);
            try buffer.loadBitmapResource(data);

            const expected =
                \\1919
                \\5D5D
                \\E6E6
                \\A2A2
            ;

            try expectPixels(expected, buffer.storage);
        }

        test "drawString renders pixels of glyph at specified position in buffer" {
            var buffer = new(Storage, 42, 18);
            buffer.fill(0x0);

            const string = "Hello\nWorld";
            try buffer.drawString(string, 0x1, .{ .x = 1, .y = 1 });

            const expected =
                \\000000000000000000000000000000000000000000
                \\010000100000000000001000000010000000000000
                \\010000100000000000001000000010000000000000
                \\010000100001110000001000000010000001110000
                \\011111100010001000001000000010000010001000
                \\010000100011111000001000000010000010001000
                \\010000100010000000001000000010000010001000
                \\010000100001111000001000000010000001110000
                \\000000000000000000000000000000000000000000
                \\010000010000000000000000000010000000001000
                \\010000010000000000000000000010000000001000
                \\010000010001110000100110000010000001111000
                \\010000010010001000111000000010000010001000
                \\010010010010001000100000000010000010001000
                \\010101010010001000100000000010000010001000
                \\011000110001110000100000000010000001111000
                \\000000000000000000000000000000000000000000
                \\000000000000000000000000000000000000000000
            ;

            try expectPixels(expected, buffer.storage);
        }

        test "drawString returns error.OutOfBounds for glyphs that are not fully inside the buffer" {
            var buffer = new(Storage, 10, 10);

            try testing.expectError(error.GlyphOutOfBounds, buffer.drawString("_", 0xB, .{ .x = -1, .y = -2 }));
            try testing.expectError(error.GlyphOutOfBounds, buffer.drawString("_", 0xB, .{ .x = 312, .y = 192 }));
        }

        test "drawString returns error.InvalidCharacter for characters that don't have glyphs defined" {
            var buffer = new(Storage, 10, 10);

            try testing.expectError(error.InvalidCharacter, buffer.drawString("\u{0}", 0xB, .{ .x = 1, .y = 1 }));
        }

        test "drawPolygon draws a single-unit square polygon as a dot" {
            const poly = Polygon.new(
                .{ .solid_color = 0x1 },
                &.{
                    .{ .x = 1, .y = 1 },
                    .{ .x = 1, .y = 2 },
                    .{ .x = 1, .y = 2 },
                    .{ .x = 1, .y = 1 },
                },
            );
            try testing.expect(poly.isDot());

            var buffer = new(Storage, 4, 4);
            var mask_buffer = new(Storage, 4, 4);

            buffer.fill(0x0);
            mask_buffer.fill(0xF);

            const expected =
                \\0000
                \\0100
                \\0000
                \\0000
            ;

            try buffer.drawPolygon(poly, &mask_buffer);
            try expectPixels(expected, buffer.storage);
        }

        test "drawPolygon draws a many-sided polygon" {
            const poly = Polygon.new(
                .{ .solid_color = 0x1 },
                &.{
                    .{ .x = 3, .y = 1 },
                    .{ .x = 4, .y = 2 },
                    .{ .x = 2, .y = 4 },
                    .{ .x = 1, .y = 4 },
                    .{ .x = 1, .y = 2 },
                    .{ .x = 2, .y = 1 },
                },
            );

            var buffer = new(Storage, 6, 6);
            var mask_buffer = new(Storage, 6, 6);

            buffer.fill(0x0);
            mask_buffer.fill(0xF);

            const expected =
                \\000000
                \\001100
                \\011110
                \\011100
                \\000000
                \\000000
            ;

            try buffer.drawPolygon(poly, &mask_buffer);
            try expectPixels(expected, buffer.storage);
        }

        test "drawPolygon with malformed bounds does not draw offscreen" {
            var poly = Polygon.new(
                .{ .solid_color = 0x1 },
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

            var buffer = new(Storage, 6, 6);
            var mask_buffer = new(Storage, 6, 6);

            buffer.fill(0x0);
            mask_buffer.fill(0xF);

            const expected =
                \\000000
                \\000000
                \\000000
                \\000000
                \\000000
                \\000000
            ;

            try buffer.drawPolygon(poly, &mask_buffer);
            try expectPixels(expected, buffer.storage);
        }

        test "drawPolygon with too few vertices returns error.VertexCountTooLow" {
            const poly = Polygon.new(.highlight, &.{
                .{ .x = 3, .y = 0 },
                .{ .x = 4, .y = 1 },
                .{ .x = 2, .y = 2 },
            });

            var buffer = new(Storage, 6, 6);
            const mask_buffer = new(Storage, 6, 6);

            try testing.expectError(error.VertexCountTooLow, buffer.drawPolygon(poly, &mask_buffer));
        }

        test "drawPolygon with vertices too far apart returns error.InvalidVertexDelta" {
            const poly = Polygon.new(.highlight, &.{
                .{ .x = 1, .y = 0 },
                .{ .x = 1, .y = 16384 },
                .{ .x = 0, .y = 16384 },
                .{ .x = 0, .y = 0 },
            });

            var buffer = new(Storage, 6, 6);
            const mask_buffer = new(Storage, 6, 6);

            try testing.expectError(error.InvalidVerticalDelta, buffer.drawPolygon(poly, &mask_buffer));
        }

        test "drawPolygon with backtracked vertices returns error.InvalidVertexDelta" {
            const poly = Polygon.new(.highlight, &.{
                .{ .x = 1, .y = 0 },
                .{ .x = 1, .y = -1 },
                .{ .x = 0, .y = -1 },
                .{ .x = 0, .y = 0 },
            });

            var buffer = new(Storage, 6, 6);
            const mask_buffer = new(Storage, 6, 6);

            try testing.expectError(error.InvalidVerticalDelta, buffer.drawPolygon(poly, &mask_buffer));
        }
    };
}

test "Run tests with aligned storage" {
    runTests(AlignedStorage.Instance);
}

test "Run tests with packed storage" {
    runTests(PackedStorage.Instance);
}
