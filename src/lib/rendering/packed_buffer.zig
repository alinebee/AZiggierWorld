//! This file defines a video buffer type that matches the reference implementation's
//! memory-saving technique of packing 2 16-color pixels into each byte of the buffer:
//! This makes a 320x200 buffer only require 32,000 bytes instead of 64,0000.
//!
//! Since pixels don't fall on byte boundaries, masking must be used to address individual pixels,
//! which complicates some of the draw routines: e.g. efficient span-drawing for polygon fills
//! must take into account whether the start and end of the span fall on byte boundaries.
//!
//! (This Zig implementation takes advantage of Zig's packed structs and sub-byte integer sizes,
//! addressing both pixels of a byte using a byte-length struct containing two 4-bit fields.
//! Behind the scenes Zig takes care of the masking for us.)

const anotherworld = @import("../anotherworld.zig");

const ColorID = @import("color_id.zig").ColorID;
const Palette = @import("palette.zig").Palette;
const PolygonDrawMode = @import("polygon_draw_mode.zig").PolygonDrawMode;
const Point = @import("point.zig").Point;
const Range = @import("range.zig").Range;
const BoundingBox = @import("bounding_box.zig").BoundingBox;

const Surface = @import("surface.zig").Surface;
const indexed_bitmap = @import("test_helpers/indexed_bitmap.zig");
const planar_bitmap = @import("planar_bitmap.zig");

const std = @import("std");
const mem = std.mem;
const math = std.math;

/// Returns a video buffer that packs 2 pixels into a single byte,
/// like the original Another World's buffers did.
pub fn PackedBuffer(comptime width: usize, comptime height: usize) type {
    const bytes_per_row = comptime try math.divCeil(usize, width, 2);
    const bytes_required = comptime height * bytes_per_row;
    const Data = [bytes_required]NativeColor;

    return struct {
        data: Data = undefined,

        /// The bounding box that encompasses all legal points within this buffer.
        pub const bounds = BoundingBox.init(0, 0, width - 1, height - 1);

        const Self = @This();

        /// Renders a single pixel or a horizontal span of pixels into a packed buffer
        /// using one of three draw operations: solid color, highlight or mask.
        pub const DrawOperation = struct {
            draw_index_fn: *const fn (self: DrawOperation, buffer: *Self, index: Index) void,
            draw_range_fn: *const fn (self: DrawOperation, buffer: *Self, range: Range(usize)) void,
            context: union {
                solid_color: NativeColor,
                highlight: void,
                mask: *const Self,
            },

            /// Creates a new draw operation that can render into a packed buffer of this size
            /// using the specified draw mode.
            pub fn forMode(draw_mode: PolygonDrawMode, mask_source: *const Self) DrawOperation {
                return switch (draw_mode) {
                    .solid_color => |color| solidColor(color),
                    .highlight => highlight(),
                    .mask => mask(mask_source),
                };
            }

            /// Construct a new draw operation that replaces pixels in the destination buffer
            /// with a solid color.
            pub fn solidColor(color: ColorID) DrawOperation {
                return .{
                    .context = .{ .solid_color = filledColor(color) },
                    .draw_index_fn = &drawSolidColorPixel,
                    .draw_range_fn = &drawSolidColorRange,
                };
            }

            /// Construct a new draw operation that highlights existing pixels within the buffer.
            pub fn highlight() DrawOperation {
                return .{
                    .context = .{ .highlight = {} },
                    .draw_index_fn = &drawHighlightPixel,
                    .draw_range_fn = &drawHighlightRange,
                };
            }

            /// Construct a new draw operation that replaces pixels in the destination buffer
            /// with the pixels at the same location in the source buffer.
            pub fn mask(source: *const Self) DrawOperation {
                return .{
                    .context = .{ .mask = source },
                    .draw_index_fn = &drawMaskPixel,
                    .draw_range_fn = &drawMaskRange,
                };
            }

            /// Fills a single pixel at the specified index using this draw operation.
            /// `index` is not bounds-checked: specifying an index outside the buffer results in undefined behaviour.
            fn drawPixel(self: DrawOperation, buffer: *Self, index: Index) void {
                self.draw_index_fn(self, buffer, index);
            }

            /// Given a byte-aligned range of bytes within the buffer, fills all pixels within those bytes
            /// using this draw operation to determine the appropriate color(s).
            /// `range` is not bounds-checked: specifying a range outside the buffer, or with a negative length,
            /// results in undefined behaviour.
            fn drawRange(self: DrawOperation, buffer: *Self, range: Range(usize)) void {
                self.draw_range_fn(self, buffer, range);
            }

            // -- Private methods --

            fn fillPixel(buffer: *Self, index: Index, color: NativeColor) void {
                const destination = &buffer.data[index.offset];
                switch (index.hand) {
                    .left => destination.*.left = color.left,
                    .right => destination.*.right = color.right,
                }
            }

            fn drawSolidColorPixel(operation: DrawOperation, buffer: *Self, index: Index) void {
                fillPixel(buffer, index, operation.context.solid_color);
            }

            fn drawHighlightPixel(_: DrawOperation, buffer: *Self, index: Index) void {
                const highlighted_color = highlightedColor(buffer.data[index.offset]);
                fillPixel(buffer, index, highlighted_color);
            }

            fn drawMaskPixel(operation: DrawOperation, buffer: *Self, index: Index) void {
                const mask_color = operation.context.mask.data[index.offset];
                fillPixel(buffer, index, mask_color);
            }

            fn drawSolidColorRange(operation: DrawOperation, buffer: *Self, range: Range(usize)) void {
                const destination_slice = buffer.data[range.min..range.max];

                mem.set(NativeColor, destination_slice, operation.context.solid_color);
            }

            fn drawHighlightRange(_: DrawOperation, buffer: *Self, range: Range(usize)) void {
                const destination_slice = buffer.data[range.min..range.max];

                for (destination_slice) |*byte| {
                    byte.* = highlightedColor(byte.*);
                }
            }

            fn drawMaskRange(operation: DrawOperation, buffer: *Self, range: Range(usize)) void {
                const destination_slice = buffer.data[range.min..range.max];
                const mask_slice = operation.context.mask.data[range.min..range.max];

                mem.copy(NativeColor, destination_slice, mask_slice);
            }
        };

        // -- Type-level functions

        /// Given an X,Y point, returns the index of the byte within `data` containing that point's pixel.
        /// This is not bounds-checked: specifying a point outside the buffer results in undefined behaviour.
        fn uncheckedIndexOf(point: Point) Index {
            const unsigned_x = @intCast(usize, point.x);
            const unsigned_y = @intCast(usize, point.y);
            const offset_of_row = unsigned_y * bytes_per_row;

            return .{
                .offset = offset_of_row + (unsigned_x / 2),
                .hand = if (unsigned_x % 2 == 0) .left else .right,
            };
        }

        // -- Public instance methods --

        /// Render the contents of the buffer into a 24-bit host surface.
        pub fn renderToSurface(self: Self, surface: *Surface(width, height), palette: Palette) void {
            var outputIndex: usize = 0;
            for (self.data) |native_color| {
                surface[outputIndex] = palette[native_color.left.index()];
                outputIndex += 1;
                surface[outputIndex] = palette[native_color.right.index()];
                outputIndex += 1;
            }
        }

        /// Fill the entire buffer with the specified color.
        pub fn fill(self: *Self, color: ColorID) void {
            const native_color = filledColor(color);
            mem.set(NativeColor, &self.data, native_color);
        }

        /// Copy the contents of the specified buffer into this one,
        /// positioning the top left of the destination at the specified Y offset.
        pub fn copy(self: *Self, other: *const Self, y: Point.Coordinate) void {
            // Early-out: if no offset is specified, replace the contents of the destination with the source.
            if (y == 0) {
                return mem.copy(NativeColor, &self.data, &other.data);
            }

            // Otherwise, copy the appropriate segment of the source into the appropriate segment of the destination.
            const max_y = comptime @intCast(isize, height - 1);
            if (y < -max_y or y > max_y) return;

            const top: usize = 0;
            const bottom = self.data.len;
            const offset_from_top = @as(usize, math.absCast(y)) * bytes_per_row;
            const offset_from_bottom = bottom - offset_from_top;

            if (y > 0) {
                //  Destination               Source
                //  +----------+- 0           +----------+ - 0
                //  |unmodified|              |//////////|
                //  |----------+- y           |//copied//|
                //  |//////////|              |//////////|
                //  |/replaced/|              |----------+- height - y
                //  |//////////|              |  unread  |
                //  +----------+- height      +----------+- height
                const source = other.data[top..offset_from_bottom];
                const destination = self.data[offset_from_top..bottom];
                mem.copy(NativeColor, destination, source);
            } else {
                //  Destination               Source
                //  +----------+- 0           +----------+ - 0
                //  |//////////|              |  unread  |
                //  |/replaced/|              |----------+- y
                //  |//////////|              |//////////|
                //  |----------+- height - y  |//copied//|
                //  |unmodified|              |//////////|
                //  +----------+- height      +----------+- height
                const source = other.data[offset_from_top..bottom];
                const destination = self.data[top..offset_from_bottom];
                mem.copy(NativeColor, destination, source);
            }
        }

        /// Load the contents of an Another World bitmap resource into this buffer,
        /// replacing all existing pixels.
        pub fn loadBitmapResource(self: *Self, bitmap_data: []const u8) planar_bitmap.Error!void {
            var reader = try planar_bitmap.planarBitmapReader(width, height, bitmap_data);

            for (self.data) |*native_color| {
                native_color.* = .{
                    .left = try reader.readColor(),
                    .right = try reader.readColor(),
                };
            }
        }

        /// Fill a horizontal line using the specified draw operation.
        /// This is not bounds-checked: specifying a span outside the buffer, or with a negative length,
        /// results in undefined behaviour.
        pub fn uncheckedDrawSpan(self: *Self, x_span: Range(Point.Coordinate), y: Point.Coordinate, operation: DrawOperation) void {
            var start_index = uncheckedIndexOf(.{ .x = x_span.min, .y = y });

            // Early-out for drawing single-pixel spans
            if (x_span.min == x_span.max) {
                operation.drawPixel(self, start_index);
                return;
            }

            var end_index = uncheckedIndexOf(.{ .x = x_span.max, .y = y });

            // If the start pixel doesn't fall at the "left" edge of a byte:
            // draw that pixel individually using masking, and start the span at the left edge of the next byte.
            if (start_index.hand != .left) {
                operation.drawPixel(self, start_index);
                start_index.offset += 1;
            }

            // If the end pixel doesn't fall at the "right" edge of a byte:
            // draw that pixel individually using masking and end the span at the right edge of the previous byte.
            if (end_index.hand != .right) {
                operation.drawPixel(self, end_index);
                end_index.offset -= 1;
            }

            // If there are any full bytes left between the start and end, fill them using a fast copy operation.
            if (start_index.offset <= end_index.offset) {
                const range = .{
                    .min = start_index.offset,
                    // Ranges are inclusive, but this range will be converted into a slice,
                    // and Zig's [start..end] slice syntax does not include the end offset.
                    .max = end_index.offset + 1,
                };
                operation.drawRange(self, range);
            }
        }

        /// Draw a single pixel using the specified draw operation.
        /// This is not bounds-checked: specifying a point outside the buffer results in undefined behaviour.
        pub fn uncheckedDrawDot(self: *Self, point: Point, operation: DrawOperation) void {
            var index = uncheckedIndexOf(point);
            operation.drawPixel(self, index);
        }

        // -- Test helpers --

        /// Export the content of the buffer to a bitmap for easier comparison testing.
        pub fn toBitmap(self: Self) indexed_bitmap.IndexedBitmap(width, height) {
            var bitmap: indexed_bitmap.IndexedBitmap(width, height) = .{ .data = undefined };

            // TODO: this would probably be more efficient if we iterated the buffer's data
            // instead of the bitmap's. But, this function is only used in tests right now.
            for (bitmap.data) |*row, y| {
                for (row) |*column, x| {
                    const point = Point{
                        .x = @intCast(Point.Coordinate, x),
                        .y = @intCast(Point.Coordinate, y),
                    };
                    const index = uncheckedIndexOf(point);
                    const native_color = self.data[index.offset];
                    column.* = switch (index.hand) {
                        .left => native_color.left,
                        .right => native_color.right,
                    };
                }
            }

            return bitmap;
        }

        /// Fill the buffer from the string representation of a bitmap.
        pub fn fillFromString(self: *Self, bitmap_string: []const u8) void {
            const bitmap = indexed_bitmap.IndexedBitmap(width, height).fromString(bitmap_string);

            for (bitmap.data) |row, y| {
                for (row) |column, x| {
                    const point = Point{
                        .x = @intCast(Point.Coordinate, x),
                        .y = @intCast(Point.Coordinate, y),
                    };
                    const index = uncheckedIndexOf(point);
                    const destination = &self.data[index.offset];
                    switch (index.hand) {
                        .left => destination.*.left = column,
                        .right => destination.*.right = column,
                    }
                }
            }
        }
    };
}

// -- Helper types --

/// The unit in which the buffer will read and write color values for individual pixels.
/// Two 4-bit colors are packed into a single byte: Zig packed structs have
/// endianness-dependent field order so we must flip based on endianness.
// TODO 0.10: merge these into a single packed struct with explicit integer size:
// https://github.com/ziglang/zig/pull/12379
const NativeColor = switch (@import("builtin").target.cpu.arch.endian()) {
    .Big => packed struct {
        left: ColorID,
        right: ColorID,
    },
    .Little => packed struct {
        right: ColorID,
        left: ColorID,
    },
};

/// Given a single 4-bit color, returns a pair of pixels that are both that color.
fn filledColor(color: ColorID) NativeColor {
    return .{ .left = color, .right = color };
}

/// Given a pair of colors, returns both of those colors highlighted.
fn highlightedColor(color: NativeColor) NativeColor {
    return @bitCast(NativeColor, ColorID.highlightByte(@bitCast(u8, color)));
}

/// The buffer index for a pixel at a given X,Y point.
const Index = struct {
    /// The offset of the byte containing the pixel.
    offset: usize,
    /// Whether this pixel is the "left" (top 4 bits) or "right" (bottom 4 bits) of its byte.
    hand: enum {
        left,
        right,
    },
};

// -- Tests --

const testing = @import("utils").testing;

test "PackedBuffer produces buffer of the expected size filled with zeroes." {
    const buffer = PackedBuffer(320, 200){};

    try testing.expectEqual(32_000, buffer.data.len);

    const expected_data = [_]NativeColor{filledColor(ColorID.cast(0))} ** buffer.data.len;

    try testing.expectEqual(expected_data, buffer.data);
}

test "PackedBuffer rounds up buffer size for uneven widths." {
    const buffer = PackedBuffer(319, 199){};
    const expected = 31_840; // 160 x 199
    try testing.expectEqual(expected, buffer.data.len);
}

test "PackedBuffer handles 0 width or height gracefully" {
    const zero_height = PackedBuffer(320, 0){};
    try testing.expectEqual(0, zero_height.data.len);

    const zero_width = PackedBuffer(0, 200){};
    try testing.expectEqual(0, zero_width.data.len);

    const zero_dimensions = PackedBuffer(0, 0){};
    try testing.expectEqual(0, zero_dimensions.data.len);
}

test "uncheckedIndexOf returns expected offset and handedness" {
    const Buffer = PackedBuffer(320, 200);

    try testing.expectEqual(.{ .offset = 0, .hand = .left }, Buffer.uncheckedIndexOf(.{ .x = 0, .y = 0 }));
    try testing.expectEqual(.{ .offset = 0, .hand = .right }, Buffer.uncheckedIndexOf(.{ .x = 1, .y = 0 }));
    try testing.expectEqual(.{ .offset = 1, .hand = .left }, Buffer.uncheckedIndexOf(.{ .x = 2, .y = 0 }));
    try testing.expectEqual(.{ .offset = 159, .hand = .right }, Buffer.uncheckedIndexOf(.{ .x = 319, .y = 0 }));
    try testing.expectEqual(.{ .offset = 160, .hand = .left }, Buffer.uncheckedIndexOf(.{ .x = 0, .y = 1 }));

    try testing.expectEqual(.{ .offset = 16_080, .hand = .left }, Buffer.uncheckedIndexOf(.{ .x = 160, .y = 100 }));
    try testing.expectEqual(.{ .offset = 31_840, .hand = .left }, Buffer.uncheckedIndexOf(.{ .x = 0, .y = 199 }));
    try testing.expectEqual(.{ .offset = 31_999, .hand = .right }, Buffer.uncheckedIndexOf(.{ .x = 319, .y = 199 }));
}

// zig fmt: off
test "toBitmap returns bitmap with expected contents" {
    const buffer = PackedBuffer(4, 4){
        .data = @bitCast([8]NativeColor, [_]u8{
            0x01, 0x23,
            0x45, 0x67,
            0x89, 0xAB,
            0xCD, 0xEF,
        })
    };

    const expected =
        \\0123
        \\4567
        \\89AB
        \\CDEF
    ;

    try indexed_bitmap.expectBitmap(expected, buffer.toBitmap());
}

test "fromString fills buffer with expected contents" {
    var buffer = PackedBuffer(4, 4){};
    buffer.fillFromString(
        \\0123
        \\4567
        \\89AB
        \\CDEF
    );

    const expected = @bitCast([8]NativeColor, [_]u8{
        0x01, 0x23,
        0x45, 0x67,
        0x89, 0xAB,
        0xCD, 0xEF,
    });

    try testing.expectEqual(expected, buffer.data);
}
// zig fmt: on

const buffer_test_suite = @import("test_helpers/buffer_test_suite.zig");

test "Run buffer interface tests" {
    buffer_test_suite.runTests(PackedBuffer);
}
