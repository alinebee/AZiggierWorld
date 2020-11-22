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

        /// Draw a 1-pixel-wide horizontal line filling the specified range,
        /// deciding its color according to the draw mode.
        /// Portions of the line that are out of bounds will not be drawn.
        pub fn drawSpan(self: *Self, x: Range.Instance(Point.Coordinate), y: Point.Coordinate, draw_mode: DrawMode.Enum, mask_buffer: *const Self) void {
            if (Self.bounds.y.contains(y) == false) {
                return;
            }

            const operation = Storage.DrawOperation.forMode(draw_mode, &mask_buffer.storage);
            
            // Clamp the x coordinates for the line to fit within the video buffer,
            // and bail out if it's entirely out of bounds.
            const in_bounds_x = Self.bounds.x.intersection(x) orelse return;
            self.storage.uncheckedDrawSpan(in_bounds_x, y, operation);
        }

        /// Draws the specified 8x8 glyph, positioning its top left corner at the specified point.
        /// Returns error.PointOutOfBounds if the glyph's bounds do not lie fully inside the buffer.
        pub fn drawGlyph(self: *Self, glyph: Font.Glyph, origin: Point.Instance, color: ColorID.Trusted) Error!void {
            const glyph_bounds = BoundingBox.new(origin.x, origin.y, origin.x + 8, origin.y + 8);

            if (Self.bounds.encloses(glyph_bounds) == false) {
                return error.PointOutOfBounds;
            }

            const operation = Storage.DrawOperation.solidColor(color);
            
            var cursor = origin;
            for (glyph) |row| {
                var remaining_pixels = row;
                var span_start: Point.Coordinate = cursor.x;
                var span_width: Point.Coordinate = 0;
                
                while (remaining_pixels != 0) {
                    const pixel_lit = (remaining_pixels & 0b1000_0000) != 0;
                    
                    if (pixel_lit) {
                        span_width += 1;
                    } else {
                        if (span_width > 0) {
                            const x_range = Range.new(Point.Coordinate, span_start, span_start + span_width - 1);
                            self.storage.uncheckedDrawSpan(x_range, cursor.y, operation);
                            
                            span_start += span_width;
                            span_width = 0;
                        }
                        span_start += 1;
                    }
                    
                    remaining_pixels <<= 1;
                }
                
                if (span_width > 0) {
                    const x_range = Range.new(Point.Coordinate, span_start, span_start + span_width - 1);
                    self.storage.uncheckedDrawSpan(x_range, cursor.y, operation);
                    span_start += span_width;
                    span_width = 0;
                }

                // Once we've consumed all bits in the row, move down to the next one.
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

// -- Public draw method tests --

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

// -- Internal implementation tests --

// // A fake storage instance that does nothing but record which draw methods were called internally.
// fn MockStorage(comptime width: usize, comptime height: usize) type {
//     return struct {
//         call_counts: struct {
//             uncheckedDrawPixel: usize,
//             uncheckedDrawSpan: usize,
//         } = .{ .uncheckedDrawPixel = 0, .uncheckedDrawSpan = 0 },
// 
//         const Self = @This();
// 
//         fn uncheckedDrawPixel(self: *Self, point: Point.Instance, draw_mode: DrawMode.Enum, mask_source: *const Self) void {
//             self.call_counts.uncheckedDrawPixel += 1;
//         }
// 
//         fn uncheckedDrawSpan(self: *Self, x_span: Range.Instance(Point.Coordinate), y: Point.Coordinate, draw_mode: DrawMode.Enum, mask_source: *const Self) void {
//             self.call_counts.uncheckedDrawSpan += 1;
//         }
//     };
// }
// 
// test "drawSpan uses uncheckedDrawPixel to draw spans that end up being a single pixel" {
//     var buffer = new(MockStorage, 4, 4);
//     var mask_buffer = buffer;
// 
//     // Span width is 3 pixels, but only 1 pixel of it is within bounds
//     buffer.drawSpan(.{ .min = -2, .max = 0 }, 0, .{ .solid_color = 0x9 }, &mask_buffer);
// 
//     testing.expectEqual(1, buffer.storage.call_counts.uncheckedDrawPixel);
//     testing.expectEqual(0, buffer.storage.call_counts.uncheckedDrawSpan);
// }
// 
// test "drawSpan uses uncheckedDrawSpan to draw spans wider than a single pixel" {
//     var buffer = new(MockStorage, 4, 4);
//     var mask_buffer = buffer;
// 
//     // Span width is 4 pixels, 2 pixels of which are within bounds
//     buffer.drawSpan(.{ .min = -2, .max = 1 }, 0, .{ .solid_color = 0x9 }, &mask_buffer);
// 
//     testing.expectEqual(0, buffer.storage.call_counts.uncheckedDrawPixel);
//     testing.expectEqual(1, buffer.storage.call_counts.uncheckedDrawSpan);
// }
// 
// test "drawSpan does not call draw methods when span is completely of bounds" {
//     var buffer = new(MockStorage, 4, 4);
//     var mask_buffer = buffer;
// 
//     // Span width is 3 pixels, but only 1 pixel of it is within bounds
//     buffer.drawSpan(.{ .min = -2, .max = -1 }, 0, .{ .solid_color = 0x9 }, &mask_buffer);
// 
//     testing.expectEqual(0, buffer.storage.call_counts.uncheckedDrawPixel);
//     testing.expectEqual(0, buffer.storage.call_counts.uncheckedDrawSpan);
// }
