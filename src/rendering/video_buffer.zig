//! Another World uses 320x200-pixel video buffers, where each pixel is a 16-bit color index in the current palette.
//! This VideoBuffer type abstracts away the storage mechanism of those pixels: it implements the draw operations
//! needed to render polygons and font glyphs, and defers pixel-level read and write operations to its backing storage.

const ColorID = @import("../values/color_id.zig");
const Point = @import("../values/point.zig");
const Range = @import("../values/range.zig");
const BoundingBox = @import("../values/bounding_box.zig");
const DrawMode = @import("../values/draw_mode.zig");
const Font = @import("../assets/font.zig");

const assert = @import("std").debug.assert;
const eql = @import("std").meta.eql;

/// Creates a new video buffer with a given width and height, using the specified type as backing storage.
pub fn new(comptime StorageFn: anytype, comptime width: usize, comptime height: usize) Instance(StorageFn, width, height) {
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

        /// Draws a 1px dot at the specified point in this buffer, deciding its color according to the draw mode.
        /// Returns error.PointOutOfBounds if the point does not lie within the buffer's bounds.
        pub fn drawDot(self: *Self, point: Point.Instance, draw_mode: DrawMode.Enum, mask_buffer: *const Self) Error!void {
            if (Self.bounds.contains(point) == false) {
                return error.PointOutOfBounds;
            }

            self.storage.uncheckedDrawPixel(point, draw_mode, &mask_buffer.storage);
        }

        /// Draw a 1-pixel-wide horizontal line filling the specified range,
        /// deciding its color according to the draw mode.
        /// Portions of the line that are out of bounds will not be drawn.
        pub fn drawSpan(self: *Self, x: Range.Instance(Point.Coordinate), y: Point.Coordinate, draw_mode: DrawMode.Enum, mask_buffer: *const Self) void {
            if (Self.bounds.y.contains(y) == false) {
                return;
            }

            // Clamp the x coordinates for the line to fit within the video buffer,
            // and bail out if it's entirely out of bounds.
            const in_bounds_x = Self.bounds.x.intersection(x) orelse return;

            if (in_bounds_x.min == in_bounds_x.max) {
                self.storage.uncheckedDrawPixel(.{ .x = in_bounds_x.min, .y = y }, draw_mode, &mask_buffer.storage);
            } else {
                self.storage.uncheckedDrawSpan(in_bounds_x, y, draw_mode, &mask_buffer.storage);
            }
        }

        /// Draws the specified 8x8 glyph, positioning its top left corner at the specified point.
        /// Returns error.PointOutOfBounds if the glyph's bounds do not lie fully inside the buffer.
        pub fn drawGlyph(self: *Self, glyph: Font.Glyph, origin: Point.Instance, color: ColorID.Trusted) Error!void {
            const glyph_bounds = BoundingBox.new(origin.x, origin.y, origin.x + 8, origin.y + 8);

            if (Self.bounds.encloses(glyph_bounds) == false) {
                return error.PointOutOfBounds;
            }

            var native_color = Storage.nativeColor(color);
            var cursor = origin;
            for (glyph) |row| {
                var remaining_pixels = row;
                // While there are still any bits left to draw in this row of the glyph,
                // pop the topmost bit of the row: if it's 1, draw a pixel at the next X cursor.
                // Stop drawing once all bits have been consumed or all remaining bits are 0.
                //
                // CHECKME: drawing 1 bit at a time is less efficient for two-pixels-per-byte packed buffers,
                // since we can end up doing 4 mask operations when replacing both pixels in a byte.
                // If we read off two bits at a time, we could check if we're going to draw both pixels
                // and just replace the whole byte; but the complexity of that check may end up slower
                // than just doing the masks.
                while (remaining_pixels != 0) {
                    if (remaining_pixels & 0b1000_0000 != 0) {
                        self.storage.uncheckedSetNativeColor(cursor, native_color);
                    }
                    remaining_pixels <<= 1;
                    cursor.x += 1;
                }

                // Once we've consumed all bits in the row, move down to the next one.
                cursor.x = origin.x;
                cursor.y += 1;
            }
        }
    };
}

/// The possible errors from a buffer render operation.
pub const Error = error{PointOutOfBounds};

// -- Testing --

const testing = @import("../utils/testing.zig");
const expectPixels = @import("test_helpers/storage_test_suite.zig").expectPixels;

const AlignedStorage = @import("storage/aligned_storage.zig");
const PackedStorage = @import("storage/packed_storage.zig");

/// Test each method of the video buffer interface against an arbitrary storage type.
fn runTests(comptime Storage: anytype) void {
    _ = struct {
        test "Instance calculates expected bounding box" {
            const Buffer = @TypeOf(new(Storage, 320, 200));

            testing.expectEqual(0, Buffer.bounds.x.min);
            testing.expectEqual(0, Buffer.bounds.y.min);
            testing.expectEqual(319, Buffer.bounds.x.max);
            testing.expectEqual(199, Buffer.bounds.y.max);
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

            expectPixels(expected, buffer.storage);
        }

        test "drawDot draws fixed color at point and ignores mask buffer" {
            var buffer = new(Storage, 4, 4);

            var mask_buffer = new(Storage, 4, 4);
            mask_buffer.fill(0xF);

            try buffer.drawDot(.{ .x = 3, .y = 2 }, .{ .solid_color = 0x9 }, &mask_buffer);

            const expected =
                \\0000
                \\0000
                \\0009
                \\0000
            ;

            expectPixels(expected, buffer.storage);
        }

        test "drawDot ramps translucent color at point and ignores mask buffer" {
            var buffer = new(Storage, 4, 4);
            buffer.storage.fillFromString(
                \\0123
                \\4567
                \\89AB
                \\CDEF
            );

            var mask_buffer = new(Storage, 4, 4);
            mask_buffer.fill(0xF);

            try buffer.drawDot(.{ .x = 2, .y = 1 }, .highlight, &mask_buffer);
            try buffer.drawDot(.{ .x = 0, .y = 3 }, .highlight, &mask_buffer);

            // Colors from 0...7 should have been ramped up to 8...F;
            // colors from 8...F should have been left as they are.
            const expected =
                \\0123
                \\45E7
                \\89AB
                \\CDEF
            ;

            expectPixels(expected, buffer.storage);
        }

        test "drawDot renders color from mask at point" {
            var buffer = new(Storage, 4, 4);

            var mask_buffer = new(Storage, 4, 4);
            mask_buffer.storage.fillFromString(
                \\0123
                \\4567
                \\89AB
                \\CDEF
            );

            try buffer.drawDot(.{ .x = 2, .y = 1 }, .mask, &mask_buffer);

            const expected =
                \\0000
                \\0060
                \\0000
                \\0000
            ;

            expectPixels(expected, buffer.storage);
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

            expectPixels(expected, buffer.storage);
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

            expectPixels(expected, buffer.storage);
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

            expectPixels(expected, buffer.storage);
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

            expectPixels(expected, buffer.storage);
        }

        test "drawGlyph renders pixels of glyph at specified position in buffer" {
            var buffer = new(Storage, 10, 10);

            const glyph = try Font.glyph('A');
            try buffer.drawGlyph(glyph, .{ .x = 1, .y = 1 }, 0xA);

            const expected =
                \\0000000000
                \\00AAAA0000
                \\0A0000A000
                \\0A0000A000
                \\0AAAAAA000
                \\0A0000A000
                \\0A0000A000
                \\0A0000A000
                \\0000000000
                \\0000000000
            ;

            expectPixels(expected, buffer.storage);
        }

        test "drawGlyph returns error.OutOfBounds for glyphs that are not fully inside the buffer" {
            var buffer = new(Storage, 10, 10);

            const glyph = try Font.glyph('K');

            testing.expectError(error.PointOutOfBounds, buffer.drawGlyph(glyph, .{ .x = -1, .y = -2 }, 11));
            testing.expectError(error.PointOutOfBounds, buffer.drawGlyph(glyph, .{ .x = 312, .y = 192 }, 11));
        }
    };
}

test "Run tests with aligned storage" {
    runTests(AlignedStorage.Instance);
}

test "Run tests with packed storage" {
    runTests(PackedStorage.Instance);
}
