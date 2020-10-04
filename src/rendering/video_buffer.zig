//! Another World uses 320x200-pixel video buffers, where each pixel is a 16-bit color index in the current palette.
//! This VideoBuffer type abstracts away the storage mechanism of those pixels: it implements the draw operations
//! needed to render polygons and font glyphs, and defers pixel-level read and write operations to its backing storage.

const ColorID = @import("../values/color_id.zig");
const Point = @import("../values/point.zig");
const Range = @import("../values/range.zig");
const BoundingBox = @import("../values/bounding_box.zig");
const PolygonDrawMode = @import("../values/polygon_draw_mode.zig");
const Font = @import("../assets/font.zig");

const assert = @import("std").debug.assert;
const eql = @import("std").meta.eql;

/// Creates a new video buffer with a given width and height, using the specified type as backing storage.
pub fn new(comptime Storage: anytype, comptime width: usize, comptime height: usize) Instance(Storage, width, height) {
    return .{};
}

pub fn Instance(comptime Storage: anytype, comptime width: usize, comptime height: usize) type {
    return struct {
        /// The backing storage for this video buffer, responsible for low-level pixel operations.
        storage: Storage(width, height) = .{},

        /// The bounding box that encompasses all legal points within this buffer.
        pub const bounds = BoundingBox.new(0, 0, width - 1, height - 1);

        const Self = @This();

        /// Return the color at the specified point in this buffer.
        /// Returns error.PointOutOfBounds if the point does not lie within the buffer's bounds.
        pub fn get(self: Self, point: Point.Instance) Error!ColorID.Trusted {
            if (Self.bounds.contains(point) == false) {
                return error.PointOutOfBounds;
            }

            return self.storage.get(point);
        }

        /// Set the color at the specified point in this buffer.
        /// Returns error.PointOutOfBounds if the point does not lie within the buffer's bounds.
        pub fn set(self: *Self, point: Point.Instance, color: ColorID.Trusted) Error!void {
            if (Self.bounds.contains(point) == false) {
                return error.PointOutOfBounds;
            }

            self.storage.set(point, color);
        }

        /// Fill every pixel in the buffer with the specified color.
        pub fn fill(self: *Self, color: ColorID.Trusted) void {
            self.storage.fill(color);
        }

        /// Draws a 1px dot at the specified point in this buffer, deciding its color according to the draw mode.
        /// Returns error.PointOutOfBounds if the point does not lie within the buffer's bounds.
        pub fn drawDot(self: *Self, point: Point.Instance, draw_mode: PolygonDrawMode.Enum, mask_buffer: *const Self) Error!void {
            if (Self.bounds.contains(point) == false) {
                return error.PointOutOfBounds;
            }

            const color = self.resolveColor(point, draw_mode, mask_buffer);
            self.storage.set(point, color);
        }

        /// Draw a 1-pixel-wide horizontal line filling the specified range,
        /// deciding its color according to the draw mode.
        /// Portions of the line that are out of bounds will not be drawn.
        pub fn drawSpan(self: *Self, x: Range.Instance(Point.Coordinate), y: Point.Coordinate, draw_mode: PolygonDrawMode.Enum, mask_buffer: *const Self) void {
            if (Self.bounds.x.contains(y) == false) {
                return;
            }

            // Clamp the x coordinates for the line to fit within the video buffer,
            // and bail out if it's entirely out of bounds.
            const in_bounds_x = Self.bounds.x.intersection(x) orelse return;

            var cursor = Point.Instance{ .x = in_bounds_x.min, .y = y };
            while (cursor.x <= in_bounds_x.max) : (cursor.x += 1) {
                const color = self.resolveColor(cursor, draw_mode, mask_buffer);
                self.storage.set(cursor, color);
            }
        }

        /// Draws the specified 8x8 glyph, positioning its top left corner at the specified point.
        /// Returns error.PointOutOfBounds if the glyph's bounds do not lie fully inside the buffer.
        pub fn drawGlyph(self: *Self, glyph: Font.Glyph, origin: Point.Instance, color: ColorID.Trusted) Error!void {
            const glyph_bounds = BoundingBox.new(origin.x, origin.y, origin.x + 8, origin.y + 8);

            if (Self.bounds.encloses(glyph_bounds) == false) {
                return error.PointOutOfBounds;
            }

            var cursor = origin;
            for (glyph) |row| {
                var remaining_pixels = row;
                // While there are still any bits left to draw in this row of the glyph,
                // pop the topmost bit of the row: if it's 1, draw a pixel at the next X cursor.
                // Stop drawing once all bits have been consumed or all remaining bits are 0.
                while (remaining_pixels != 0) {
                    if (remaining_pixels & 0b1000_0000 != 0) {
                        self.storage.set(cursor, color);
                    }
                    remaining_pixels <<= 1;
                    cursor.x += 1;
                }

                // Once we've consumed all bits in the row, move down to the next one.
                cursor.x = origin.x;
                cursor.y += 1;
            }
        }

        /// Determines the color to draw for the specified point based on a draw mode:
        /// - `color_id`: Draw the specified fixed color.
        /// - `translucent`: Remap the color at that point to the ramped version of the color,
        ///    to achieve translucency effects.
        /// - `mask`: replace the color at that point with the color at the same point in another buffer,
        ///    to achieve mask effects.
        /// This does not do bounds-checking: accessing an out-of-bounds point is undefined behaviour.
        fn resolveColor(self: *Self, point: Point.Instance, draw_mode: PolygonDrawMode.Enum, mask_buffer: *const Self) ColorID.Trusted {
            return switch (draw_mode) {
                .color_id => |color_id| color_id,
                .translucent => ColorID.ramp(self.storage.get(point)),
                .mask => mask_buffer.storage.get(point),
            };
        }
    };
}

/// The possible errors from a buffer render operation.
pub const Error = error{PointOutOfBounds};

// -- Testing --

const testing = @import("../utils/testing.zig");
const AlignedStorage = @import("storage/aligned_storage.zig");

test "Instance calculates expected bounding box" {
    const Buffer = @TypeOf(new(AlignedStorage.Instance, 320, 200));

    testing.expectEqual(0, Buffer.bounds.x.min);
    testing.expectEqual(0, Buffer.bounds.y.min);
    testing.expectEqual(319, Buffer.bounds.x.max);
    testing.expectEqual(199, Buffer.bounds.y.max);
}

test "get retrieves pixel at specified point" {
    var buffer = new(AlignedStorage.Instance, 4, 4);
    buffer.storage.data = .{
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 5, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    };

    testing.expectEqual(5, buffer.get(.{ .x = 2, .y = 1 }));
}

test "get returns error.pointOutOfBounds when point is not within buffer region" {
    const buffer = new(AlignedStorage.Instance, 4, 4);

    testing.expectError(error.PointOutOfBounds, buffer.get(.{ .x = 0, .y = 4 }));
    testing.expectError(error.PointOutOfBounds, buffer.get(.{ .x = -1, .y = 0 }));
}

test "set sets pixel at specified point" {
    var buffer = new(AlignedStorage.Instance, 4, 4);

    const expected_data = @TypeOf(buffer.storage.data){
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 7, 0, 0 },
    };

    try buffer.set(.{ .x = 1, .y = 3 }, 7);
    testing.expectEqual(expected_data, buffer.storage.data);
}

test "set returns error.pointOutOfBounds when point is not within buffer region" {
    var buffer = new(AlignedStorage.Instance, 4, 4);

    testing.expectError(error.PointOutOfBounds, buffer.set(.{ .x = 0, .y = 4 }, 0));
    testing.expectError(error.PointOutOfBounds, buffer.set(.{ .x = -1, .y = 0 }, 0));
}

test "fill fills buffer with specified color" {
    var buffer = new(AlignedStorage.Instance, 4, 4);
    buffer.storage.data = .{
        .{ 00, 01, 02, 03 },
        .{ 04, 05, 06, 07 },
        .{ 08, 09, 10, 11 },
        .{ 12, 13, 14, 15 },
    };

    buffer.fill(15);

    const expected_data = @TypeOf(buffer.storage.data){
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
    };

    testing.expectEqual(expected_data, buffer.storage.data);
}

test "drawDot draws fixed color at point and ignores mask buffer" {
    var buffer = new(AlignedStorage.Instance, 4, 4);
    var mask_buffer = new(AlignedStorage.Instance, 4, 4);
    mask_buffer.fill(15);

    const expected_data = @TypeOf(buffer.storage.data){
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 9 },
        .{ 0, 0, 0, 0 },
    };

    try buffer.drawDot(.{ .x = 3, .y = 2 }, .{ .color_id = 9 }, &mask_buffer);

    testing.expectEqual(expected_data, buffer.storage.data);
}

test "drawDot ramps translucent color at point and ignores mask buffer" {
    var buffer = new(AlignedStorage.Instance, 4, 4);
    var mask_buffer = new(AlignedStorage.Instance, 4, 4);
    mask_buffer.fill(15);

    buffer.storage.data = .{
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0b0011 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    };

    const expected_data = @TypeOf(buffer.storage.data){
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0b1011 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    };

    try buffer.drawDot(.{ .x = 3, .y = 1 }, .translucent, &mask_buffer);

    testing.expectEqual(expected_data, buffer.storage.data);
}

test "drawDot renders color from mask at point" {
    var buffer = new(AlignedStorage.Instance, 4, 4);
    var mask_buffer = new(AlignedStorage.Instance, 4, 4);

    buffer.storage.data = .{
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
    };

    mask_buffer.storage.data = .{
        .{ 00, 01, 02, 03 },
        .{ 04, 05, 06, 07 },
        .{ 08, 09, 10, 11 },
        .{ 12, 13, 14, 15 },
    };

    const expected_data = @TypeOf(buffer.storage.data){
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 06, 00 },
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
    };

    try buffer.drawDot(.{ .x = 2, .y = 1 }, .mask, &mask_buffer);

    testing.expectEqual(expected_data, buffer.storage.data);
}

test "drawSpan draws a horizontal line in a fixed color and ignores mask buffer, clamping line to fit within bounds" {
    var buffer = new(AlignedStorage.Instance, 4, 4);
    var mask_buffer = new(AlignedStorage.Instance, 4, 4);
    mask_buffer.fill(15);

    buffer.storage.data = .{
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
    };

    const expected_data = @TypeOf(buffer.storage.data){
        .{ 00, 00, 00, 00 },
        .{ 09, 09, 09, 00 },
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
    };

    buffer.drawSpan(.{ .min = -2, .max = 2 }, 1, .{ .color_id = 9 }, &mask_buffer);

    testing.expectEqual(expected_data, buffer.storage.data);
}

test "drawSpan ramps existing colors in a horizontal line and ignores mask buffer, clamping line to fit within bounds" {
    var buffer = new(AlignedStorage.Instance, 4, 4);
    var mask_buffer = new(AlignedStorage.Instance, 4, 4);
    mask_buffer.fill(15);

    buffer.storage.data = .{
        .{ 0, 0, 0, 0 },
        .{ 0b0001, 0b0010, 0b0011, 0b0100 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    };

    const expected_data = @TypeOf(buffer.storage.data){
        .{ 0, 0, 0, 0 },
        .{ 0b1001, 0b1010, 0b1011, 0b0100 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    };

    buffer.drawSpan(.{ .min = -2, .max = 2 }, 1, .translucent, &mask_buffer);

    testing.expectEqual(expected_data, buffer.storage.data);
}

test "drawSpan renders horizontal line from mask pixels, clamping line to fit within bounds" {
    var buffer = new(AlignedStorage.Instance, 4, 4);
    var mask_buffer = new(AlignedStorage.Instance, 4, 4);

    buffer.storage.data = .{
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
    };

    mask_buffer.storage.data = .{
        .{ 00, 01, 02, 03 },
        .{ 04, 05, 06, 07 },
        .{ 08, 09, 10, 11 },
        .{ 12, 13, 14, 15 },
    };

    const expected_data = @TypeOf(buffer.storage.data){
        .{ 00, 00, 00, 00 },
        .{ 04, 05, 06, 00 },
        .{ 00, 00, 00, 00 },
        .{ 00, 00, 00, 00 },
    };

    buffer.drawSpan(.{ .min = -2, .max = 2 }, 1, .mask, &mask_buffer);

    testing.expectEqual(expected_data, buffer.storage.data);
}

test "drawSpan draws no pixels when line is completely out of bounds" {
    var buffer = new(AlignedStorage.Instance, 4, 4);
    var mask_buffer = new(AlignedStorage.Instance, 4, 4);
    mask_buffer.fill(15);

    const expected_data = @TypeOf(buffer.storage.data){
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    };

    buffer.drawSpan(.{ .min = -2, .max = 2 }, 4, .{ .color_id = 9 }, &mask_buffer);

    testing.expectEqual(expected_data, buffer.storage.data);
}

test "drawGlyph renders pixels of glyph at specified position in buffer" {
    var buffer = new(AlignedStorage.Instance, 10, 10);

    const glyph = try Font.glyph('A');
    try buffer.drawGlyph(glyph, .{ .x = 1, .y = 1 }, 15);

    // 'A' glyph:
    // 0b01111000,
    // 0b10000100,
    // 0b10000100,
    // 0b11111100,
    // 0b10000100,
    // 0b10000100,
    // 0b10000100,
    // 0b00000000,

    const expected_data = @TypeOf(buffer.storage.data){
        .{ 00, 00, 00, 00, 00, 00, 00, 00, 00, 00 },
        .{ 00, 00, 15, 15, 15, 15, 00, 00, 00, 00 },
        .{ 00, 15, 00, 00, 00, 00, 15, 00, 00, 00 },
        .{ 00, 15, 00, 00, 00, 00, 15, 00, 00, 00 },
        .{ 00, 15, 15, 15, 15, 15, 15, 00, 00, 00 },
        .{ 00, 15, 00, 00, 00, 00, 15, 00, 00, 00 },
        .{ 00, 15, 00, 00, 00, 00, 15, 00, 00, 00 },
        .{ 00, 15, 00, 00, 00, 00, 15, 00, 00, 00 },
        .{ 00, 00, 00, 00, 00, 00, 00, 00, 00, 00 },
        .{ 00, 00, 00, 00, 00, 00, 00, 00, 00, 00 },
    };

    testing.expectEqual(expected_data, buffer.storage.data);
}

test "drawGlyph returns error.OutOfBounds for glyphs that are not fully inside the buffer" {
    var buffer = new(AlignedStorage.Instance, 10, 10);

    const glyph = try Font.glyph('K');

    testing.expectError(error.PointOutOfBounds, buffer.drawGlyph(glyph, .{ .x = -1, .y = -2 }, 11));
    testing.expectError(error.PointOutOfBounds, buffer.drawGlyph(glyph, .{ .x = 312, .y = 192 }, 11));
}
