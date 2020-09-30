//! Another World uses 320x200-pixel video buffers, where each pixel is a 16-bit color index in the current palette.
//! This VideoBuffer type abstracts away the storage mechanism of those pixels: it implements the draw operations
//! needed to render polygons and font glyphs, and defers pixel-level read and write operations to its backing storage.

const ColorID = @import("../values/color_id.zig");
const Point = @import("../values/point.zig");
const BoundingBox = @import("../values/bounding_box.zig");
const PolygonDrawMode = @import("../values/polygon_draw_mode.zig");

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
        pub const bounds = BoundingBox.Instance{
            .min_x = 0,
            .min_y = 0,
            .max_x = width - 1,
            .max_y = height - 1,
        };

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

    testing.expectEqual(0, Buffer.bounds.min_x);
    testing.expectEqual(0, Buffer.bounds.min_y);
    testing.expectEqual(319, Buffer.bounds.max_x);
    testing.expectEqual(199, Buffer.bounds.max_y);
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
