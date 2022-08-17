const anotherworld = @import("../anotherworld.zig");

const Color = @import("color.zig").Color;
const mem = @import("std").mem;

/// Returns the type of a 24-bit rendering surface that has the specified width and height.
pub fn Surface(comptime width: usize, comptime height: usize) type {
    return [width * height]Color;
}

/// Creates a new 24-bit rendering surface of the specified width and height, filled with the specified color.
pub fn filledSurface(comptime SurfaceType: type, color: Color) SurfaceType {
    var surface: SurfaceType = undefined;
    mem.set(Color, &surface, color);
    return surface;
}

// -- Tests --

const testing = anotherworld.testing;

test "Instance matches the size of a raw u8 buffer" {
    const width = 320;
    const height = 200;
    const expected_size = width * height * 4;

    const RawType = [expected_size]u8;
    const SurfaceType = Surface(width, height);

    try testing.expectEqual(expected_size, @sizeOf(RawType));
    try testing.expectEqual(expected_size, @sizeOf(SurfaceType));
}

test "filledSurface fills entire buffer with specified color" {
    const SurfaceType = Surface(10, 10);
    const color = Color{ .r = 1, .g = 2, .b = 3, .a = 255 };

    var expected: SurfaceType = undefined;
    mem.set(Color, &expected, color);

    const actual = filledSurface(SurfaceType, color);

    try testing.expectEqual(expected, actual);
}
