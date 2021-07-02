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
    comptime const Data = [bytes_required]NativeColor;

    return struct {
        data: Data = mem.zeroes(Data),

        const Self = @This();

        /// Renders a single pixel or a horizontal span of pixels into a packed buffer
        /// using one of three draw operations: solid color, highlight or mask.
        pub const DrawOperation = struct {
            draw_index_fn: fn (self: DrawOperation, buffer: *Self, index: Index) void,
            draw_range_fn: fn (self: DrawOperation, buffer: *Self, range: Range.Instance(usize)) void,
            context: union {
                solid_color: NativeColor,
                highlight: void,
                mask: *const Self,
            },

            /// Creates a new draw operation that can render into a packed buffer of this size
            /// using the specified draw mode.
            pub fn forMode(draw_mode: DrawMode.Enum, mask_source: *const Self) DrawOperation {
                return switch (draw_mode) {
                    .solid_color => |color| solidColor(color),
                    .highlight => highlight(),
                    .mask => mask(mask_source),
                };
            }

            /// Construct a new draw operation that replaces pixels in the destination buffer
            /// with a solid color.
            pub fn solidColor(color: ColorID.Trusted) DrawOperation {
                return .{
                    .context = .{ .solid_color = filledColor(color) },
                    .draw_index_fn = drawSolidColorPixel,
                    .draw_range_fn = drawSolidColorRange,
                };
            }

            /// Construct a new draw operation that highlights existing pixels within the buffer.
            pub fn highlight() DrawOperation {
                return .{
                    .context = .{ .highlight = {} },
                    .draw_index_fn = drawHighlightPixel,
                    .draw_range_fn = drawHighlightRange,
                };
            }

            /// Construct a new draw operation that replaces pixels in the destination buffer
            /// with the pixels at the same location in the source buffer.
            pub fn mask(source: *const Self) DrawOperation {
                return .{
                    .context = .{ .mask = source },
                    .draw_index_fn = drawMaskPixel,
                    .draw_range_fn = drawMaskRange,
                };
            }

            /// Fills a single pixel at the specified index using this draw operation.
            /// `index` is not bounds-checked: specifying an index outside the buffer results in undefined behaviour.
            fn drawPixel(self: DrawOperation, buffer: *Self, index: Index) void {
                self.draw_index_fn(self, buffer, index);
            }

            /// Given a byte-aligned range of bytes within the buffer storage, fills all pixels within those bytes
            /// using this draw operation to determine the appropriate color(s).
            /// `range` is not bounds-checked: specifying a range outside the buffer, or with a negative length,
            /// results in undefined behaviour.
            fn drawRange(self: DrawOperation, buffer: *Self, range: Range.Instance(usize)) void {
                self.draw_range_fn(self, buffer, range);
            }

            // -- Private methods --

            fn fillPixel(buffer: *Self, index: Index, color: NativeColor) void {
                var destination = &buffer.data[index.offset];
                switch (index.hand) {
                    .left => destination.*.left = color.left,
                    .right => destination.*.right = color.right,
                }
            }

            fn drawSolidColorPixel(self: DrawOperation, buffer: *Self, index: Index) void {
                fillPixel(buffer, index, self.context.solid_color);
            }

            fn drawHighlightPixel(self: DrawOperation, buffer: *Self, index: Index) void {
                const highlighted_color = highlightedColor(buffer.data[index.offset]);
                fillPixel(buffer, index, highlighted_color);
            }

            fn drawMaskPixel(self: DrawOperation, buffer: *Self, index: Index) void {
                const mask_color = self.context.mask.data[index.offset];
                fillPixel(buffer, index, mask_color);
            }

            fn drawSolidColorRange(self: DrawOperation, buffer: *Self, range: Range.Instance(usize)) void {
                const destination_slice = buffer.data[range.min..range.max];

                mem.set(NativeColor, destination_slice, self.context.solid_color);
            }

            fn drawHighlightRange(self: DrawOperation, buffer: *Self, range: Range.Instance(usize)) void {
                const destination_slice = buffer.data[range.min..range.max];

                for (destination_slice) |*byte| {
                    byte.* = highlightedColor(byte.*);
                }
            }

            fn drawMaskRange(self: DrawOperation, buffer: *Self, range: Range.Instance(usize)) void {
                const destination_slice = buffer.data[range.min..range.max];
                const mask_slice = self.context.mask.data[range.min..range.max];

                mem.copy(NativeColor, destination_slice, mask_slice);
            }
        };

        // -- Type-level functions

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
            const native_color = filledColor(color);
            mem.set(NativeColor, &self.data, native_color);
        }

        /// Fill a horizontal line using the specified draw operation.
        /// This is not bounds-checked: specifying a span outside the buffer, or with a negative length,
        /// results in undefined behaviour.
        pub fn uncheckedDrawSpan(self: *Self, x_span: Range.Instance(Point.Coordinate), y: Point.Coordinate, operation: DrawOperation) void {
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

            // If there are any full bytes left between the start and end, fill them using a fast range operation.
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
            const bitmap = IndexedBitmap.Instance(width, height).fromString(bitmap_string);

            for (bitmap.data) |row, y| {
                for (row) |column, x| {
                    const point = Point.Instance{
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

/// The unit in which the buffer will read and write pixel color values.
/// Two 4-bit colors are packed into a single byte: Zig packed structs
/// have endianness-dependent field order so we must flip based on endianness.
/// q.v.:
const NativeColor = if (std.Target.current.cpu.arch.endian() == .Big)
    packed struct {
        left: ColorID.Trusted,
        right: ColorID.Trusted,
    }
else
    packed struct {
        right: ColorID.Trusted,
        left: ColorID.Trusted,
    };

fn filledColor(color: ColorID.Trusted) NativeColor {
    return .{ .left = color, .right = color };
}

fn highlightedColor(color: NativeColor) NativeColor {
    return @bitCast(NativeColor, ColorID.highlightByte(@bitCast(u8, color)));
}

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

    try testing.expectEqual(32_000, storage.data.len);

    const expected_data = [_]NativeColor{filledColor(0)} ** storage.data.len;

    try testing.expectEqual(expected_data, storage.data);
}

test "Instance rounds up storage size for uneven pixel counts." {
    const storage = Instance(319, 199){};
    try testing.expectEqual(31_741, storage.data.len);
}

test "Instance handles 0 width or height gracefully" {
    const zero_height = Instance(320, 0){};
    try testing.expectEqual(0, zero_height.data.len);

    const zero_width = Instance(0, 200){};
    try testing.expectEqual(0, zero_width.data.len);

    const zero_dimensions = Instance(0, 0){};
    try testing.expectEqual(0, zero_dimensions.data.len);
}

test "uncheckedIndexOf returns expected offset and handedness" {
    const Storage = Instance(320, 200);

    try testing.expectEqual(.{ .offset = 0, .hand = .left }, Storage.uncheckedIndexOf(.{ .x = 0, .y = 0 }));
    try testing.expectEqual(.{ .offset = 0, .hand = .right }, Storage.uncheckedIndexOf(.{ .x = 1, .y = 0 }));
    try testing.expectEqual(.{ .offset = 1, .hand = .left }, Storage.uncheckedIndexOf(.{ .x = 2, .y = 0 }));
    try testing.expectEqual(.{ .offset = 159, .hand = .right }, Storage.uncheckedIndexOf(.{ .x = 319, .y = 0 }));
    try testing.expectEqual(.{ .offset = 160, .hand = .left }, Storage.uncheckedIndexOf(.{ .x = 0, .y = 1 }));

    try testing.expectEqual(.{ .offset = 16_080, .hand = .left }, Storage.uncheckedIndexOf(.{ .x = 160, .y = 100 }));
    try testing.expectEqual(.{ .offset = 31_840, .hand = .left }, Storage.uncheckedIndexOf(.{ .x = 0, .y = 199 }));
    try testing.expectEqual(.{ .offset = 31_999, .hand = .right }, Storage.uncheckedIndexOf(.{ .x = 319, .y = 199 }));
}

// zig fmt: off
test "toBitmap returns bitmap with expected contents" {
    const storage = Instance(4, 4){
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

    try IndexedBitmap.expectBitmap(expected, storage.toBitmap());
}

test "fromString fills buffer with expected contents" {
    var storage = Instance(4, 4){};
    storage.fillFromString(
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

    try testing.expectEqual(expected, storage.data);
}
// zig fmt: on

const storage_test_suite = @import("../test_helpers/storage_test_suite.zig");

test "Run storage interface tests" {
    storage_test_suite.runTests(Instance);
}
