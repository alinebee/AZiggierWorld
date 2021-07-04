//! Another World uses 320x200-pixel video buffers, where each pixel is a 16-bit color index in the current palette.
//! This VideoBuffer type abstracts away the storage mechanism of those pixels: it implements the draw operations
//! needed to render polygons and font glyphs, and defers pixel-level read and write operations to its backing storage.

const ColorID = @import("../values/color_id.zig");
const Point = @import("../values/point.zig");
const Range = @import("../values/range.zig");
const BoundingBox = @import("../values/bounding_box.zig");
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

        /// Draw a 1-pixel-wide horizontal line filling the specified range,
        /// deciding its color according to the draw mode.
        /// Portions of the line that are out of bounds will not be drawn.
        pub fn drawSpan(self: *Self, x: Range.Instance(Point.Coordinate), y: Point.Coordinate, draw_mode: DrawMode.Enum, mask_buffer: *const Self) void {
            if (Self.bounds.y.contains(y) == false) return;

            // Clamp the x coordinates for the line to fit within the video buffer,
            // and bail out if it's entirely out of bounds.
            const in_bounds_x = Self.bounds.x.intersection(x) orelse return;

            const operation = Storage.DrawOperation.forMode(draw_mode, &mask_buffer.storage);
            self.storage.uncheckedDrawSpan(in_bounds_x, y, operation);
        }

        /// Draws the specified 8x8 glyph in a solid color, positioning its top left corner at the specified point.
        /// Returns error.GlyphOutOfBounds if the glyph's bounds do not lie fully inside the buffer.
        pub fn drawGlyph(self: *Self, glyph: Font.Glyph, origin: Point.Instance, color: ColorID.Trusted) Error!void {
            const glyph_bounds = BoundingBox.new(origin.x, origin.y, origin.x + 8, origin.y + 8);

            if (Self.bounds.encloses(glyph_bounds) == false) {
                return error.GlyphOutOfBounds;
            }

            const operation = Storage.DrawOperation.solidColor(color);

            var cursor = origin;

            // Walk through each row of the glyph drawing spans of lit pixels.
            for (glyph) |row| {
                var remaining_pixels = row;
                var span_start: Point.Coordinate = cursor.x;
                var span_width: Point.Coordinate = 0;

                while (remaining_pixels != 0) {
                    const pixel_lit = (remaining_pixels & 0b1000_0000) != 0;
                    remaining_pixels <<= 1;

                    // Accumulate lit pixels into a single span for more efficient drawing.
                    if (pixel_lit == true) span_width += 1;

                    // If we reach an unlit pixel, or the last lit pixel of the row,
                    // draw the current span of lit pixels and start a new span.
                    if (pixel_lit == false or remaining_pixels == 0) {
                        if (span_width > 0) {
                            const x_range = Range.new(Point.Coordinate, span_start, span_start + span_width - 1);
                            self.storage.uncheckedDrawSpan(x_range, cursor.y, operation);

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
        /// - polygon.count == 0.
        /// - any vertex along the right-hand side of the polygon is higher than the previous vertex.
        /// - any vertex along the right-hand side of the polygon is > 1023 units below the previous vertex.
        pub fn drawPolygon(self: *Self, polygon: Polygon.Instance, mask_buffer: *const Self) Error!void {
            if (polygon.count < 4) {
                return error.InvalidVertexCount;
            }

            // Skip if none of the polygon is on-screen
            if (Self.bounds.intersects(polygon.bounds) == false) {
                return;
            }

            const origin = polygon.bounds.origin();
            const operation = Storage.DrawOperation.forMode(polygon.draw_mode, &mask_buffer.storage);

            // Early-out for polygons that cover a single screen pixel
            if (polygon.isDot()) {
                self.storage.uncheckedDrawSpan(.{ .min = origin.x, .max = origin.x }, origin.y, operation);
                return;
            }

            // Another World polygons are stored as lists of vertices clockwise from the top
            // of the polygon back up to the top. Each vertex is vertically aligned with a pair
            // at the other end of the vertex list.
            // To render the polygon, we walk the list of vertices from the start (clockwise)
            // and end (counterclockwise), pairing up the vertices and forming a quadrilateral
            // out of the two edges between that pair of vertices and the pair before them.
            var clockwise_vertex: usize = 0;
            var counterclockwise_vertex: usize = polygon.count - 1;

            // 16.16 fixed-point math ahoy!
            // The reference implementation tracked the X coordinates of the polygon as 32-bit values:
            // the top 16 bits are the whole coordinates, and the bottom 16 bits are the fractional
            // components of each, which accumulate and roll over into the whole coordinate
            // as the routine traverses the edges of the polygon.
            //
            // (We could rewrite all of this to use floating-point math instead but where's the fun in that?)
            var clockwise_x = FixedPrecision.new(polygon.vertices[clockwise_vertex].x);
            var counterclockwise_x = FixedPrecision.new(polygon.vertices[counterclockwise_vertex].x);
            var y = polygon.vertices[clockwise_vertex].y;

            clockwise_vertex += 1;
            counterclockwise_vertex -= 1;

            // Walk through each pair of vertices, drawing spans of pixels between them.
            while (clockwise_vertex < counterclockwise_vertex) {
                // When calculating X offsets for this pair of edges, carry over the whole-number X coordinates
                // from the previous edges but wipe out any accumulated fractions.
                // DOCUMENT ME: What's up with these magic numbers for the fraction?
                // Why aren't they the same for each?
                clockwise_x.setFraction(0x8000);
                counterclockwise_x.setFraction(0x7FFF);

                // For each pair of edges, determine the number of rows to draw,
                // and calculate the slope of each edge as a step value representing
                // how much to change X between each row.
                const clockwise_delta = polygon.vertices[clockwise_vertex].x - polygon.vertices[clockwise_vertex - 1].x;
                const counterclockwise_delta = polygon.vertices[counterclockwise_vertex].x - polygon.vertices[counterclockwise_vertex + 1].x;
                const vertical_delta = math.cast(VerticalDelta, polygon.vertices[clockwise_vertex].y - polygon.vertices[clockwise_vertex - 1].y) catch {
                    return Error.InvalidVerticalDelta;
                };

                const clockwise_step = stepDistance(clockwise_delta, vertical_delta);
                const counterclockwise_step = stepDistance(counterclockwise_delta, vertical_delta);

                // If there's a vertical change between vertices,
                // draw a horizontal span for each unit of vertical difference.
                if (vertical_delta > 0) {
                    var rows_remaining = vertical_delta;

                    while (rows_remaining > 0) : (rows_remaining -= 1) {
                        // Don't draw parts of the polygon that are off the top of the buffer,
                        // but still accumulate their changes to x.
                        if (y >= Self.bounds.x.min) {
                            const x1 = clockwise_x.whole();
                            const x2 = counterclockwise_x.whole();

                            // Flip the span if needed to ensure it always runs from left to right.
                            // This handles vertices that cross in the middle.
                            const x_range: Range.Instance(Point.Coordinate) = if (x1 < x2) .{ .min = x1, .max = x2 } else .{ .min = x2, .max = x1 };

                            // Only draw if the resulting span is within the buffer's bounds
                            if (Self.bounds.x.intersection(x_range)) |clamped_range| {
                                self.storage.uncheckedDrawSpan(clamped_range, y, operation);
                            }
                        }

                        y += 1;

                        // Stop drawing immediately if we ever leave the bottom of the buffer.
                        if (y > Self.bounds.y.max) return;

                        // Otherwise, accumulate the step changes and move down to the next row.
                        clockwise_x.add(clockwise_step);
                        counterclockwise_x.add(counterclockwise_step);
                    }
                } else {
                    // If there has been no vertical change (i.e. the edges are horizontal), don't draw a span:
                    // just accumulate any changes to the x offsets, which will apply to the next pair of edges.
                    clockwise_x.add(clockwise_step);
                    counterclockwise_x.add(counterclockwise_step);
                }

                clockwise_vertex += 1;
                counterclockwise_vertex -= 1;
            }
        }
    };
}

/// A signed fixed-point number with 16 bits of precision for the whole part
/// and 16 bits of precision for the fraction.
const FixedPrecision = struct {
    raw: i32,

    const Self = @This();

    /// Create a new fixed precision value from a whole number.
    fn new(_whole: i16) Self {
        return .{ .raw = @intCast(i32, _whole) << 16 };
    }

    /// The whole component of the number.
    fn whole(self: Self) i16 {
        return @truncate(i16, self.raw >> 16);
    }

    /// The fractional component of the number.
    fn fraction(self: Self) u16 {
        return @truncate(u16, self.raw);
    }

    /// Set a new fractional component of the number.
    fn setFraction(self: *Self, _fraction: u16) void {
        self.raw = @bitCast(i32, (@bitCast(u32, self.raw) & 0xFFFF_0000) | _fraction);
    }

    /// Add two fixed-precision numbers together.
    fn add(self: *Self, other: Self) void {
        self.raw +%= other.raw;
    }
};

// -- Precomputed slopes --

const VerticalDelta = u10;
const max_vertical_delta = math.maxInt(VerticalDelta);

/// A lookup table of fixed-point x/y ratios for slopes of heights between 0 and `max_vertical_delta`.
/// The values in this table will be multiplied by the x component of a vector to calculate the x step
/// for each unit of y along the vector of {x,y}.
const precomputed_slopes = init: {
    var table: [max_vertical_delta]u16 = undefined;

    const base = 1 << 14;
    table[0] = base;
    var index: u16 = 1;

    @setEvalBranchQuota(max_vertical_delta);
    while (index < table.len) : (index += 1) {
        table[index] = base / index;
    }

    break :init table;
};

/// Given an {x, y} vector, calculates the step to add to x for each unit of y
/// to draw a slope along that vector.
fn stepDistance(delta_x: Point.Coordinate, delta_y: VerticalDelta) FixedPrecision {
    const slope = precomputed_slopes[delta_y];

    return .{
        // The slope table uses 14 bits of precision for the fractional component.
        // The final result must then be left-shifted by 2 to arrive at the desired 16.16 precision.
        .raw = (@intCast(i32, delta_x) * @intCast(i32, slope)) << 2,
    };
}

/// The possible errors from buffer render operations.
pub const Error = error{
    GlyphOutOfBounds,
    InvalidVerticalDelta,
    InvalidVertexCount,
};

// -- Testing --

const testing = @import("../utils/testing.zig");
const expectPixels = @import("test_helpers/storage_test_suite.zig").expectPixels;

const AlignedStorage = @import("storage/aligned_storage.zig");
const PackedStorage = @import("storage/packed_storage.zig");

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

        test "drawSpan draws a horizontal line in a fixed color and ignores mask buffer, clamping line to fit within bounds" {
            var buffer = new(Storage, 4, 4);

            var mask_buffer = new(Storage, 4, 4);
            mask_buffer.fill(0xF);

            buffer.drawSpan(.{ .min = -2, .max = 2 }, 1, .{ .solid_color = 0x9 }, &mask_buffer);

            const expected =
                \\0000
                \\9990
                \\0000
                \\0000
            ;

            try expectPixels(expected, buffer.storage);
        }

        test "drawSpan highlights existing colors in a horizontal line and ignores mask buffer, clamping line to fit within bounds" {
            var buffer = new(Storage, 4, 4);
            buffer.storage.fillFromString(
                \\0123
                \\0123
                \\0123
                \\0123
            );

            var mask_buffer = new(Storage, 4, 4);
            mask_buffer.fill(0xF);

            buffer.drawSpan(.{ .min = -2, .max = 2 }, 1, .highlight, &mask_buffer);

            // Colors from 0...7 should have been ramped up to 8...F;
            // colors from 8...F should have been left as they are.
            const expected =
                \\0123
                \\89A3
                \\0123
                \\0123
            ;

            try expectPixels(expected, buffer.storage);
        }

        test "drawSpan copies mask pixels in horizontal line, clamping line to fit within bounds" {
            var buffer = new(Storage, 4, 4);

            var mask_buffer = new(Storage, 4, 4);
            mask_buffer.storage.fillFromString(
                \\0123
                \\4567
                \\89AB
                \\CDEF
            );

            buffer.drawSpan(.{ .min = -2, .max = 2 }, 1, .mask, &mask_buffer);

            const expected =
                \\0000
                \\4560
                \\0000
                \\0000
            ;

            try expectPixels(expected, buffer.storage);
        }

        test "drawSpan draws no pixels when line is completely out of bounds" {
            var buffer = new(Storage, 4, 4);

            var mask_buffer = new(Storage, 4, 4);
            mask_buffer.fill(0xF);

            buffer.drawSpan(.{ .min = -2, .max = 2 }, 4, .{ .solid_color = 0x9 }, &mask_buffer);

            const expected =
                \\0000
                \\0000
                \\0000
                \\0000
            ;

            try expectPixels(expected, buffer.storage);
        }

        test "drawGlyph renders pixels of glyph at specified position in buffer" {
            var buffer = new(Storage, 10, 10);

            const glyph = try Font.glyph('Q');
            try buffer.drawGlyph(glyph, .{ .x = 1, .y = 1 }, 0x1);

            const expected =
                \\0000000000
                \\0011110000
                \\0100001000
                \\0100001000
                \\0100001000
                \\0100001000
                \\0100011000
                \\0011111000
                \\0000000110
                \\0000000000
            ;

            try expectPixels(expected, buffer.storage);
        }

        test "drawGlyph returns error.OutOfBounds for glyphs that are not fully inside the buffer" {
            var buffer = new(Storage, 10, 10);

            const glyph = try Font.glyph('K');

            try testing.expectError(error.GlyphOutOfBounds, buffer.drawGlyph(glyph, .{ .x = -1, .y = -2 }, 11));
            try testing.expectError(error.GlyphOutOfBounds, buffer.drawGlyph(glyph, .{ .x = 312, .y = 192 }, 11));
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
    };
}

test "Run tests with aligned storage" {
    runTests(AlignedStorage.Instance);
}

test "Run tests with packed storage" {
    runTests(PackedStorage.Instance);
}
