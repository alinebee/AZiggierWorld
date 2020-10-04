const ColorID = @import("../../values/color_id.zig");
const Point = @import("../../values/point.zig");

const std = @import("std");
const mem = std.mem;
const math = std.math;
const introspection = @import("introspection.zig");

/// Returns a video buffer storage that packs 2 pixels into a single byte,
/// like the original Another World's buffers did.
pub fn Instance(comptime width: usize, comptime height: usize) type {
    comptime const bytes_required = try math.divCeil(usize, width * height, 2);

    return struct {
        data: [bytes_required]u8 = [_]u8{0} ** bytes_required,

        const Self = @This();

        /// Return the color at the specified point in the buffer.
        /// This is not bounds-checked: specifying an point outside the buffer results in undefined behaviour.
        pub fn uncheckedGet(self: Self, point: Point.Instance) ColorID.Trusted {
            const index = self.uncheckedIndexOf(point);
            const byte = self.data[index.offset];

            return @truncate(ColorID.Trusted, switch (index.hand) {
                .left => byte >> 4,
                .right => byte,
            });
        }

        /// Set the color at the specified point in the buffer.
        /// This is not bounds-checked: specifying an point outside the buffer results in undefined behaviour.
        pub fn uncheckedSet(self: *Self, point: Point.Instance, color: ColorID.Trusted) void {
            const index = self.uncheckedIndexOf(point);
            const byte = &self.data[index.offset];

            byte.* = switch (index.hand) {
                .left => (byte.* & 0b0000_1111) | (@as(u8, color) << 4),
                .right => (byte.* & 0b1111_0000) | color,
            };
        }

        /// Fill the entire buffer with the specified color.
        pub fn fill(self: *Self, color: ColorID.Trusted) void {
            const color_byte = (@as(u8, color) << 4) | color;
            mem.set(u8, &self.data, color_byte);
        }

        /// Given an X,Y point, returns the index of the byte within `data` containing that point's pixel,
        /// and whether the point is the left or right pixel in the byte.
        /// This is not bounds-checked: specifying a point outside the buffer results in undefined behaviour.
        fn uncheckedIndexOf(self: Self, point: Point.Instance) Index {
            comptime const signed_width = @intCast(isize, width);
            const signed_address = @divFloor(point.x + (point.y * signed_width), 2);

            return .{
                .offset = @intCast(usize, signed_address),
                .hand = if (@rem(point.x, 2) == 0) .left else .right,
            };
        }
    };
}

/// The storage index for a pixel at a given point.
const Index = struct {
    /// The offset of the byte containing the pixel.
    offset: usize,
    /// Whether this pixel is the "left" (top 4 bits) or "right" (bottom 4 bits) of the byte.
    hand: enum(u1) {
        left,
        right,
    },
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
    const storage = Instance(320, 200){};

    testing.expectEqual(.{ .offset = 0, .hand = .left }, storage.uncheckedIndexOf(.{ .x = 0, .y = 0 }));
    testing.expectEqual(.{ .offset = 0, .hand = .right }, storage.uncheckedIndexOf(.{ .x = 1, .y = 0 }));
    testing.expectEqual(.{ .offset = 1, .hand = .left }, storage.uncheckedIndexOf(.{ .x = 2, .y = 0 }));
    testing.expectEqual(.{ .offset = 159, .hand = .right }, storage.uncheckedIndexOf(.{ .x = 319, .y = 0 }));
    testing.expectEqual(.{ .offset = 160, .hand = .left }, storage.uncheckedIndexOf(.{ .x = 0, .y = 1 }));

    testing.expectEqual(.{ .offset = 16_080, .hand = .left }, storage.uncheckedIndexOf(.{ .x = 160, .y = 100 }));
    testing.expectEqual(.{ .offset = 31_840, .hand = .left }, storage.uncheckedIndexOf(.{ .x = 0, .y = 199 }));
    testing.expectEqual(.{ .offset = 31_999, .hand = .right }, storage.uncheckedIndexOf(.{ .x = 319, .y = 199 }));

    // Uncomment to trigger runtime errors in test builds
    // _ = storage.uncheckedIndexOf(.{ .x = 0, .y = 200 });
    // _ = storage.uncheckedIndexOf(.{ .x = -1, .y = 0 });
}

test "uncheckedGet returns color at point" {
    var storage = Instance(320, 200){};
    storage.data[3] = 0b1010_0101;

    testing.expectEqual(0b0000, storage.uncheckedGet(.{ .x = 5, .y = 0 }));
    testing.expectEqual(0b1010, storage.uncheckedGet(.{ .x = 6, .y = 0 }));
    testing.expectEqual(0b0101, storage.uncheckedGet(.{ .x = 7, .y = 0 }));
}

test "uncheckedSet sets color at point" {
    var storage = Instance(320, 200){};

    storage.uncheckedSet(.{ .x = 6, .y = 0 }, 0b1010);
    storage.uncheckedSet(.{ .x = 7, .y = 0 }, 0b0101);

    testing.expectEqual(0b1010_0101, storage.data[3]);
}

test "fill replaces all bytes in buffer with specified color" {
    const fill_color: ColorID.Trusted = 0b0101;
    const color_byte: u8 = 0b0101_0101;

    var storage = Instance(320, 200){};

    const before_fill = [_]u8{0} ** storage.data.len;
    const after_fill = [_]u8{color_byte} ** storage.data.len;

    testing.expectEqual(before_fill, storage.data);

    storage.fill(fill_color);

    testing.expectEqual(after_fill, storage.data);
}
