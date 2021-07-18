const ColorID = @import("../../values/color_id.zig");
const Point = @import("../../values/point.zig");
const Range = @import("../../values/range.zig");
const DrawMode = @import("../../values/draw_mode.zig");

const IndexedBitmap = @import("../test_helpers/indexed_bitmap.zig");

const mem = @import("std").mem;
const math = @import("std").math;

/// Returns a video buffer storage that stores a single pixel per byte.
pub fn Instance(comptime width: usize, comptime height: usize) type {
    comptime const Row = [width]ColorID.Trusted;
    comptime const Data = [height]Row;

    return struct {
        data: Data = mem.zeroes(Data),

        const Self = @This();

        /// Renders a horizontal span of pixels into an aligned buffer
        /// using one of three draw operations: solid color, highlight or mask.
        pub const DrawOperation = struct {
            draw_fn: fn (self: DrawOperation, buffer: *Self, row: usize, start_column: usize, end_column: usize) void,
            context: union {
                solid_color: ColorID.Trusted,
                highlight: void,
                mask: *const Self,
            },

            /// Creates a new draw operation that can render into an aligned buffer of this size
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
                    .context = .{ .solid_color = color },
                    .draw_fn = drawSolidColorRange,
                };
            }

            /// Construct a new draw operation that highlights existing pixels within the buffer.
            pub fn highlight() DrawOperation {
                return .{
                    .context = .{ .highlight = {} },
                    .draw_fn = drawHighlightRange,
                };
            }

            /// Construct a new draw operation that replaces pixels in the destination buffer
            /// with the pixels at the same location in the source buffer.
            pub fn mask(source: *const Self) DrawOperation {
                return .{
                    .context = .{ .mask = source },
                    .draw_fn = drawMaskRange,
                };
            }

            /// Given a byte-aligned range of bytes within the buffer storage, fills all pixels within those bytes
            /// using this draw operation to determine the appropriate color(s).
            /// `range` is not bounds-checked: specifying a range outside the buffer, or with a negative length,
            /// results in undefined behaviour.
            fn drawRange(self: DrawOperation, buffer: *Self, row: usize, start_column: usize, end_column: usize) void {
                self.draw_fn(self, buffer, row, start_column, end_column);
            }

            // -- Private methods --

            fn drawSolidColorRange(self: DrawOperation, buffer: *Self, row: usize, start_column: usize, end_column: usize) void {
                var destination_slice = buffer.data[row][start_column..end_column];
                mem.set(NativeColor, destination_slice, self.context.solid_color);
            }

            fn drawHighlightRange(self: DrawOperation, buffer: *Self, row: usize, start_column: usize, end_column: usize) void {
                var destination_slice = buffer.data[row][start_column..end_column];
                for (destination_slice) |*pixel| {
                    pixel.* = ColorID.highlight(pixel.*);
                }
            }

            fn drawMaskRange(self: DrawOperation, buffer: *Self, row: usize, start_column: usize, end_column: usize) void {
                var destination_slice = buffer.data[row][start_column..end_column];
                const mask_slice = self.context.mask.data[row][start_column..end_column];
                mem.copy(NativeColor, destination_slice, mask_slice);
            }
        };

        // -- Public instance methods --

        /// Fill the entire buffer with the specified color.
        pub fn fill(self: *Self, color: ColorID.Trusted) void {
            // It would be nice to use mem.set on self.data as a whole,
            // but that doesn't work on multidimensional arrays.
            for (self.data) |*row| {
                mem.set(ColorID.Trusted, row, color);
            }
        }

        /// Copy the contents of the specified storage into this one,
        /// positioning the top left of the destination at the specified Y offset.
        pub fn copy(self: *Self, other: *const Self, y: Point.Coordinate) void {
            // Early-out: if no offset is specified, just replace the destination with the source.
            if (y == 0) {
                return mem.copy(Row, &self.data, &other.data);
            }

            // Otherwise, copy the appropriate slice of the source into the appropriate slice of the destination.
            comptime const max_y = @intCast(isize, height - 1);
            if (y < -max_y or y > max_y) return;

            comptime const top: usize = 0;
            comptime const bottom = self.data.len;
            const offset_from_top = @as(usize, math.absCast(y));
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
                mem.copy(Row, destination, source);
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
                mem.copy(Row, destination, source);
            }
        }

        /// Load the contents of an Another World bitmap resource into this buffer,
        /// replacing all existing pixels.
        pub fn loadBitmapResource(self: *Self, bitmap_data: []const u8) PlanarBitmapResource.Error!void {
            var reader = try PlanarBitmapResource.new(width, height, bitmap_data);

            for (self.data) |*row| {
                for (row.*) |*color| {
                    color.* = try reader.readColor();
                }
            }
        }

        /// Fill a horizontal line with colors using the specified draw mode.
        /// This is not bounds-checked: specifying a span outside the buffer, or with a negative length,
        /// results in undefined behaviour.
        pub fn uncheckedDrawSpan(self: *Self, x_span: Range.Instance(Point.Coordinate), y: Point.Coordinate, operation: DrawOperation) void {
            const row = @intCast(usize, y);
            const start_column = @intCast(usize, x_span.min);

            // Ranges are inclusive, but this range will be converted into a slice,
            // and Zig's [start..end] slice syntax does not include the end offset.
            const end_column = @intCast(usize, x_span.max) + 1;

            operation.drawRange(self, row, start_column, end_column);
        }

        /// Draw a single pixel using the specified draw operation.
        /// This is not bounds-checked: specifying a point outside the buffer results in undefined behaviour.
        pub fn uncheckedDrawDot(self: *Self, point: Point.Instance, operation: DrawOperation) void {
            // TODO: add optimized functions to DrawOperation that avoid loops?
            const row = @intCast(usize, point.y);
            const column = @intCast(usize, point.x);
            operation.drawRange(self, row, column, column + 1);
        }

        // -- Test helpers --

        /// Export the content of the buffer to a bitmap for easier comparison testing.
        pub fn toBitmap(self: Self) IndexedBitmap.Instance(width, height) {
            return IndexedBitmap.Instance(width, height){ .data = self.data };
        }

        /// Create a new buffer from the string representation of a bitmap.
        pub fn fillFromString(self: *Self, bitmap_string: []const u8) void {
            const bitmap = IndexedBitmap.Instance(width, height).fromString(bitmap_string);
            self.data = bitmap.data;
        }
    };
}

// The unit in which the buffer will read and write pixel color values.
const NativeColor = ColorID.Trusted;

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "Instance produces storage of the expected size filled with zeroes." {
    const storage = Instance(320, 200){};

    const ExpectedData = [200][320]NativeColor;

    try testing.expectEqual(ExpectedData, @TypeOf(storage.data));

    const expected_data = mem.zeroes(ExpectedData);

    try testing.expectEqual(expected_data, storage.data);
}

test "Instance handles 0 width or height gracefully" {
    const zero_height = Instance(320, 0){};
    try testing.expectEqual([0][320]NativeColor, @TypeOf(zero_height.data));

    const zero_width = Instance(0, 200){};
    try testing.expectEqual([200][0]NativeColor, @TypeOf(zero_width.data));

    const zero_dimensions = Instance(0, 0){};
    try testing.expectEqual([0][0]NativeColor, @TypeOf(zero_dimensions.data));
}

const storage_test_suite = @import("../test_helpers/storage_test_suite.zig");

test "Run storage interface tests" {
    storage_test_suite.runTests(Instance);
}
