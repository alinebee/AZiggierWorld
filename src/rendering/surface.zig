const Color = @import("../values/color.zig");
const mem = @import("std").mem;

/// Creates a new 24-bit rendering surface of the specified width and height, filled with the specified color.
pub fn filled(comptime Surface: type, color: Color.Instance) Surface {
    var surface: Surface = undefined;
    mem.set(Color.Instance, &surface, color);
    return surface;
}

/// Returns the type of a 24-bit rendering surface that has the specified width and height.
pub fn Instance(comptime width: usize, comptime height: usize) type {
    return [width * height]Color.Instance;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "Instance matches the size of a raw u8 buffer" {
    const width = 320;
    const height = 200;
    const expected_size = width * height * 3;

    const RawType = [expected_size]u8;
    const SurfaceType = Instance(width, height);

    try testing.expectEqual(expected_size, @sizeOf(RawType));
    try testing.expectEqual(expected_size, @sizeOf(SurfaceType));
}

test "filled fills entire buffer with specified color" {
    const SurfaceType = Instance(10, 10);
    const color = Color.Instance{ .r = 1, .g = 2, .b = 3 };

    var expected: SurfaceType = undefined;
    mem.set(Color.Instance, &expected, color);

    const actual = filled(SurfaceType, color);

    try testing.expectEqual(expected, actual);
}
