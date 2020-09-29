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

pub fn Instance(comptime StorageFactory: StorageFactoryFn, comptime width: usize, comptime height: usize) type {
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
        pub fn get(self: *Self, point: Point.Instance) Error!ColorID.Trusted {
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

        /// Draws a 1px dot at the specified point in this buffer, deciding its color according to the draw mode.
        /// Returns error.PointOutOfBounds if the point does not lie within the buffer's bounds.
        pub fn drawDot(self: *Self, point: Point.Instance, draw_mode: PolygonDrawMode.Enum, mask_buffer: anytype) Error!void {
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
        fn resolveColor(self: *Self, point: Point.Instance, draw_mode: PolygonDrawMode.Enum, mask_buffer: anytype) ColorID.Trusted {
            // Enforce that the mask buffer must have the same dimensions as this one,
            // since we access values at the same coordinate in both buffers.
            comptime const MaskType = @TypeOf(mask_buffer.*);
            comptime assert(eql(Self.bounds, MaskType.bounds));

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
const MockStorage = @import("storage/mock_storage.zig");

test "Instance calculates expected bounding box" {
    const Storage = MockStorage.new(struct {});
    const Buffer = @TypeOf(new(Storage.new, 320, 200));

    testing.expectEqual(0, Buffer.bounds.min_x);
    testing.expectEqual(0, Buffer.bounds.min_y);
    testing.expectEqual(319, Buffer.bounds.max_x);
    testing.expectEqual(199, Buffer.bounds.max_y);
}

test "new passes width and height to storage type" {
    const Storage = MockStorage.new(struct {});

    var buffer = new(Storage.new, 320, 200);

    testing.expectEqual(320, @TypeOf(buffer.storage).width);
    testing.expectEqual(200, @TypeOf(buffer.storage).height);
}

test "get defers to storage implementation" {
    const Storage = MockStorage.new(struct {
        pub fn get(point: Point.Instance) ColorID.Trusted {
            testing.expectEqual(.{ .x = 0, .y = 0 }, point);
            return 15;
        }
    });

    var buffer = new(Storage.new, 320, 200);

    testing.expectEqual(15, buffer.get(.{ .x = 0, .y = 0 }));
    testing.expectEqual(1, buffer.storage.call_counts.get);
}

test "get returns error.pointOutOfBounds when point is not within buffer region" {
    const Storage = MockStorage.new(struct {
        pub fn get(point: Point.Instance) ColorID.Trusted {
            unreachable;
        }
    });

    var buffer = new(Storage.new, 320, 200);

    testing.expectError(error.PointOutOfBounds, buffer.get(.{ .x = 0, .y = 200 }));
    testing.expectError(error.PointOutOfBounds, buffer.get(.{ .x = -1, .y = 0 }));
}

test "set defers to storage implementation" {
    const Storage = MockStorage.new(struct {
        pub fn set(point: Point.Instance, color_id: ColorID.Trusted) void {
            testing.expectEqual(.{ .x = 0, .y = 0 }, point);
            testing.expectEqual(7, color_id);
        }
    });

    var buffer = new(Storage.new, 320, 200);

    try buffer.set(.{ .x = 0, .y = 0 }, 7);
    testing.expectEqual(1, buffer.storage.call_counts.set);
}

test "set returns error.pointOutOfBounds when point is not within buffer region" {
    const Storage = MockStorage.new(struct {
        pub fn set(point: Point.Instance, color_id: ColorID.Trusted) void {
            unreachable;
        }
    });

    var buffer = new(Storage.new, 320, 200);

    testing.expectError(error.PointOutOfBounds, buffer.set(.{ .x = 0, .y = 200 }, 0));
    testing.expectError(error.PointOutOfBounds, buffer.set(.{ .x = -1, .y = 0 }, 0));
}

test "drawDot draws fixed color at point" {
    const fixed_color = 2;

    const Storage = MockStorage.new(struct {
        pub fn get(point: Point.Instance) ColorID.Trusted {
            unreachable;
        }

        pub fn set(point: Point.Instance, color_id: ColorID.Trusted) void {
            testing.expectEqual(.{ .x = 0, .y = 0 }, point);
            testing.expectEqual(fixed_color, color_id);
        }
    });

    const MaskStorage = MockStorage.new(struct {
        pub fn get(point: Point.Instance) ColorID.Trusted {
            unreachable;
        }
    });

    var buffer = new(Storage.new, 320, 200);
    var mask_buffer = new(MaskStorage.new, 320, 200);

    try buffer.drawDot(.{ .x = 0, .y = 0 }, .{ .color_id = fixed_color }, &mask_buffer);

    testing.expectEqual(1, buffer.storage.call_counts.set);
    testing.expectEqual(0, buffer.storage.call_counts.get);
    testing.expectEqual(0, mask_buffer.storage.call_counts.get);
}

test "drawDot ramps translucent color at point" {
    const source_color: ColorID.Trusted = 0b0011;
    const ramped_color: ColorID.Trusted = 0b1011;

    const Storage = MockStorage.new(struct {
        pub fn get(point: Point.Instance) ColorID.Trusted {
            testing.expectEqual(.{ .x = 0, .y = 0 }, point);
            return source_color;
        }

        pub fn set(point: Point.Instance, color_id: ColorID.Trusted) void {
            testing.expectEqual(.{ .x = 0, .y = 0 }, point);
            testing.expectEqual(ramped_color, color_id);
        }
    });

    const MaskStorage = MockStorage.new(struct {
        pub fn get(point: Point.Instance) ColorID.Trusted {
            unreachable;
        }
    });

    var buffer = new(Storage.new, 320, 200);
    var mask_buffer = new(MaskStorage.new, 320, 200);

    try buffer.drawDot(.{ .x = 0, .y = 0 }, .translucent, &mask_buffer);

    testing.expectEqual(1, buffer.storage.call_counts.set);
    testing.expectEqual(1, buffer.storage.call_counts.get);
}

test "drawDot renders color from mask at point" {
    const source_color: ColorID.Trusted = 8;

    const Storage = MockStorage.new(struct {
        pub fn get(point: Point.Instance) ColorID.Trusted {
            unreachable;
        }

        pub fn set(point: Point.Instance, color_id: ColorID.Trusted) void {
            testing.expectEqual(.{ .x = 0, .y = 0 }, point);
            testing.expectEqual(source_color, color_id);
        }
    });

    const MaskStorage = MockStorage.new(struct {
        pub fn get(point: Point.Instance) ColorID.Trusted {
            testing.expectEqual(.{ .x = 0, .y = 0 }, point);
            return source_color;
        }
    });

    var buffer = new(Storage.new, 320, 200);
    var mask_buffer = new(MaskStorage.new, 320, 200);

    try buffer.drawDot(.{ .x = 0, .y = 0 }, .mask, &mask_buffer);

    testing.expectEqual(1, buffer.storage.call_counts.set);
    testing.expectEqual(1, mask_buffer.storage.call_counts.get);
}
