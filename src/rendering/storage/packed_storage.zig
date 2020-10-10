const ColorID = @import("../../values/color_id.zig");
const Point = @import("../../values/point.zig");
const Range = @import("../../values/range.zig");
const DrawMode = @import("../../values/draw_mode.zig");

const IndexedBitmap = @import("../test_helpers/indexed_bitmap.zig");

const std = @import("std");
const mem = std.mem;
const math = std.math;

/// Returns a video buffer storage that packs 2 pixels into a single byte,
/// like the original Another World's buffers did.
pub fn Instance(comptime width: usize, comptime height: usize) type {
    comptime const bytes_required = try math.divCeil(usize, width * height, 2);

    return struct {
        const Self = @This();

        data: [bytes_required]NativeColor = [_]NativeColor{0} ** bytes_required,

        // -- Type-level functions

        /// Widens a 4-bit color into a byte representing two pixels of that color.
        /// Intended to be passed to `uncheckedSetNativeColor` for more efficient drawing.
        pub fn nativeColor(color: ColorID.Trusted) NativeColor {
            return (@as(u8, color) << 4) | color;
        }

        /// Given an X,Y point, returns the index of the byte within `data` containing that point's pixel.
        /// This is not bounds-checked: specifying a point outside the buffer results in undefined behaviour.
        fn uncheckedIndexOf(point: Point.Instance) Index {
            comptime const signed_width = @intCast(isize, width);
            const signed_offset = @divFloor(point.x + (point.y * signed_width), 2);

            return .{
                .offset = @intCast(usize, signed_offset),
                .hand = Handedness.of(point.x),
            };
        }

        // -- Public instance methods --

        /// Fill the entire buffer with the specified color.
        pub fn fill(self: *Self, color: ColorID.Trusted) void {
            const native_color = nativeColor(color);
            mem.set(NativeColor, &self.data, native_color);
        }

        /// Draws a single pixel at the specified point, deriving its color from the specified draw mode.
        /// Used for drawing single-pixel polygons.
        /// This is not bounds-checked: specifying a point outside the buffer results in undefined behaviour.
        pub fn uncheckedDrawPixel(self: *Self, point: Point.Instance, draw_mode: DrawMode.Enum, mask_source: *const Self) void {
            const index = uncheckedIndexOf(point);
            self.uncheckedDrawIndex(index, draw_mode, mask_source);
        }

        /// Sets a single pixel at the specified point to the specified color.
        /// Used for drawing solid font glyphs, which don't need the extra complexity of `uncheckedDrawPixel`.
        /// This is not bounds-checked: specifying a point outside the buffer results in undefined behaviour.
        pub fn uncheckedSetNativeColor(self: *Self, point: Point.Instance, native_color: NativeColor) void {
            const index = uncheckedIndexOf(point);
            self.uncheckedSetIndex(index, native_color);
        }

        /// Fill a horizontal line with colors using the specified draw mode.
        /// This is not bounds-checked: specifying a span outside the buffer, or with a negative length,
        /// results in undefined behaviour.
        pub fn uncheckedDrawSpan(self: *Self, x_span: Range.Instance(Point.Coordinate), y: Point.Coordinate, draw_mode: DrawMode.Enum, mask_source: *const Self) void {
            var start_index = uncheckedIndexOf(.{ .x = x_span.min, .y = y });
            var end_index = uncheckedIndexOf(.{ .x = x_span.max, .y = y });

            // If the start pixel doesn't fall at the "left" edge of a byte:
            // draw that pixel the hard way using masking, and start the span at the left edge of the next byte.
            if (start_index.hand != .left) {
                self.uncheckedDrawIndex(start_index, draw_mode, mask_source);
                start_index.offset += 1;
            }

            // If the end pixel doesn't fall at the "right" edge of a byte:
            // draw that pixel the hard way using masking and end the span at the right edge of the previous byte.
            if (end_index.hand != .right) {
                self.uncheckedDrawIndex(end_index, draw_mode, mask_source);
                end_index.offset -= 1;
            }

            // If there are any full bytes left between the start and end, fill them using a fast operation.
            if (start_index.offset <= end_index.offset) {
                const range = .{
                    .min = start_index.offset,
                    // Ranges are inclusive, but this range will be converted into a slice,
                    // and Zig's [start..end] slice syntax does not include the end offset.
                    .max = end_index.offset + 1,
                };
                self.uncheckedDrawRange(range, draw_mode, mask_source);
            }
        }

        // -- Private instance methods --

        /// Draws a single pixel at the specified index, deriving its color from the specified draw mode.
        /// Used internally by `uncheckedDrawPixel` and `uncheckedDrawSpan`.
        /// `index` is not bounds-checked: specifying an index outside the buffer results in undefined behaviour.
        fn uncheckedDrawIndex(self: *Self, index: Index, draw_mode: DrawMode.Enum, mask_source: *const Self) void {
            const native_color = switch (draw_mode) {
                .solid_color => |color_id| Self.nativeColor(color_id),
                .highlight => ColorID.highlightByte(self.data[index.offset]),
                .mask => mask_source.data[index.offset],
            };

            self.uncheckedSetIndex(index, native_color);
        }

        /// Sets the specified pixel of the byte at the specified index to the specified solid color.
        /// Used internally by `uncheckedDrawIndex` and `uncheckedSetNativeColor`.
        /// `index` is not bounds-checked: specifying an index outside the buffer results in undefined behaviour.
        fn uncheckedSetIndex(self: *Self, index: Index, color: NativeColor) void {
            const destination = &self.data[index.offset];

            destination.* = switch (index.hand) {
                .left => (destination.* & 0b0000_1111) | (color & 0b1111_0000),
                .right => (destination.* & 0b1111_0000) | (color & 0b0000_1111),
            };
        }

        /// Given a range of bytes within the buffer storage, fills all pixels within those bytes,
        /// using the specified draw mode to determine the appropriate color(s).
        /// Used internally by `uncheckedDrawSpan`, and equivalent to a multibyte version of `uncheckedDrawIndex`.
        /// `range` is not bounds-checked: specifying a range outside the buffer, or with a negative length,
        /// results in undefined behaviour.
        fn uncheckedDrawRange(self: *Self, range: Range.Instance(usize), draw_mode: DrawMode.Enum, mask_source: *const Self) void {
            var destination_slice = self.data[range.min..range.max];

            switch (draw_mode) {
                .solid_color => |color_id| {
                    mem.set(NativeColor, destination_slice, Self.nativeColor(color_id));
                },
                .highlight => {
                    for (destination_slice) |*byte| {
                        byte.* = ColorID.highlightByte(byte.*);
                    }
                },
                .mask => {
                    const mask_slice = mask_source.data[range.min..range.max];
                    mem.copy(NativeColor, destination_slice, mask_slice);
                },
            }
        }

        // -- Test helpers --

        /// Export the content of the buffer to a bitmap for easier comparison testing.
        pub fn toBitmap(self: Self) IndexedBitmap.Instance(width, height) {
            var bitmap: IndexedBitmap.Instance(width, height) = .{ .data = undefined };

            for (bitmap.data) |*row, y| {
                for (row) |*column, x| {
                    const point = Point.Instance{
                        .x = @intCast(Point.Coordinate, x),
                        .y = @intCast(Point.Coordinate, y),
                    };
                    const index = uncheckedIndexOf(point);
                    const color_byte = self.data[index.offset];
                    column.* = @truncate(ColorID.Trusted, switch (index.hand) {
                        .left => color_byte >> 4,
                        .right => color_byte,
                    });
                }
            }

            return bitmap;
        }

        /// Fill the buffer from the string representation of a bitmap.
        pub fn fillFromString(self: *Self, bitmap_string: []const u8) void {
            const bitmap = IndexedBitmap.Instance(width, height).fromString(bitmap_string);

            for (bitmap.data) |row, y| {
                for (row) |column, x| {
                    const point = Point.Instance{
                        .x = @intCast(Point.Coordinate, x),
                        .y = @intCast(Point.Coordinate, y),
                    };
                    const native_color = nativeColor(column);
                    self.uncheckedSetNativeColor(point, native_color);
                }
            }
        }
    };
}

// The unit in which the buffer will read and write pixel color values.
const NativeColor = u8;

/// Whether a pixel is the "left" (top 4 bits) or "right" (bottom 4 bits) of the byte.
const Handedness = enum(u1) {
    left,
    right,

    /// Given an X coordinate, returns whether it falls into the left or right of the byte.
    fn of(x: Point.Coordinate) Handedness {
        return if (@rem(x, 2) == 0) .left else .right;
    }
};

/// The storage index for a pixel at a given point.
const Index = struct {
    /// The offset of the byte containing the pixel.
    offset: usize,
    /// Whether this pixel is the "left" (top 4 bits) or "right" (bottom 4 bits) of the byte.
    hand: Handedness,
};

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "Instance produces storage of the expected size filled with zeroes." {
    const storage = Instance(320, 200){};

    testing.expectEqual(32_000, storage.data.len);

    const expected_data = [_]u8{0} ** storage.data.len;

    testing.expectEqual(expected_data, storage.data);
}

test "Instance rounds up storage size for uneven pixel counts." {
    const storage = Instance(319, 199){};
    testing.expectEqual(31_741, storage.data.len);
}

test "Instance handles 0 width or height gracefully" {
    const zero_height = Instance(320, 0){};
    testing.expectEqual(0, zero_height.data.len);

    const zero_width = Instance(0, 200){};
    testing.expectEqual(0, zero_width.data.len);

    const zero_dimensions = Instance(0, 0){};
    testing.expectEqual(0, zero_dimensions.data.len);
}

test "uncheckedIndexOf returns expected offset and handedness" {
    const Storage = Instance(320, 200);

    testing.expectEqual(.{ .offset = 0, .hand = .left }, Storage.uncheckedIndexOf(.{ .x = 0, .y = 0 }));
    testing.expectEqual(.{ .offset = 0, .hand = .right }, Storage.uncheckedIndexOf(.{ .x = 1, .y = 0 }));
    testing.expectEqual(.{ .offset = 1, .hand = .left }, Storage.uncheckedIndexOf(.{ .x = 2, .y = 0 }));
    testing.expectEqual(.{ .offset = 159, .hand = .right }, Storage.uncheckedIndexOf(.{ .x = 319, .y = 0 }));
    testing.expectEqual(.{ .offset = 160, .hand = .left }, Storage.uncheckedIndexOf(.{ .x = 0, .y = 1 }));

    testing.expectEqual(.{ .offset = 16_080, .hand = .left }, Storage.uncheckedIndexOf(.{ .x = 160, .y = 100 }));
    testing.expectEqual(.{ .offset = 31_840, .hand = .left }, Storage.uncheckedIndexOf(.{ .x = 0, .y = 199 }));
    testing.expectEqual(.{ .offset = 31_999, .hand = .right }, Storage.uncheckedIndexOf(.{ .x = 319, .y = 199 }));
}

// zig fmt: off
test "toBitmap returns bitmap with expected contents" {
    const storage = Instance(4, 4){
        .data = .{
            0x01, 0x23,
            0x45, 0x67,
            0x89, 0xAB,
            0xCD, 0xEF,
        }
    };

    const expected =
        \\0123
        \\4567
        \\89AB
        \\CDEF
    ;

    IndexedBitmap.expectBitmap(expected, storage.toBitmap());
}

test "fromString fills buffer with expected contents" {
    var storage = Instance(4, 4){};
    storage.fillFromString(
        \\0123
        \\4567
        \\89AB
        \\CDEF
    );

    const expected = [8]u8{
        0x01, 0x23,
        0x45, 0x67,
        0x89, 0xAB,
        0xCD, 0xEF,
    };

    testing.expectEqual(expected, storage.data);
}
// zig fmt: on

const storage_test_suite = @import("../test_helpers/storage_test_suite.zig");

test "Run storage interface tests" {
    storage_test_suite.runTests(Instance);
}
