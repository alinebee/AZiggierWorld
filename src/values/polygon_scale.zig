const trait = @import("std").meta.trait;

/// The scale at which to render a polygon.
/// This is a raw value that will be divided by 64 to determine the actual scale:
/// e.g. 64 is 1x, 32 is 0.5x, 96 is 1.5x, 256 is 4x etc.
pub const Raw = u16;

/// The default scale for polygon draw operations.
/// This renders polygons at their native size.
pub const default: Raw = 64;

/// Scale a signed or unsigned integer value by the specified factor.
/// This will wrap if the scaled result is too large to fit into the target integer width.
pub fn apply(comptime Int: type, value: Int, scale: Raw) Int {
    comptime const fullwidth_type = if (trait.isUnsignedInt(Int)) usize else isize;
    comptime const divisor = @as(fullwidth_type, default);

    const scaled_value = @divTrunc(@as(fullwidth_type, value) *% @as(fullwidth_type, scale), divisor);

    return @truncate(Int, scaled_value);
}

// -- Tests --

const testing = @import("../utils/testing.zig");
const math = @import("std").math;

test "apply scales up signed values" {
    testing.expectEqual(-2674, apply(i16, -1337, default * 2));
}

test "apply scales down signed values, rounding down" {
    testing.expectEqual(-668, apply(i16, -1337, default / 2));
}

test "apply applies no scaling to signed values at default value" {
    testing.expectEqual(-1337, apply(i16, -1337, default));
}

test "apply applies no scaling to signed 0" {
    testing.expectEqual(0, apply(i16, 0, default * 2));
}

test "apply wraps signed values on overflow instead of trapping" {
    testing.expectEqual(-1536, apply(i16, math.maxInt(i16), math.maxInt(Raw)));
}

test "apply wraps signed values on underflow instead of trapping" {
    testing.expectEqual(512, apply(i16, math.minInt(i16), math.maxInt(Raw)));
}

test "apply scales up unsigned values" {
    testing.expectEqual(2674, apply(u16, 1337, default * 2));
}

test "apply scales down unsigned values, rounding down" {
    testing.expectEqual(668, apply(u16, 1337, default / 2));
}

test "apply applies no scaling to unsigned values at default value" {
    testing.expectEqual(1337, apply(u16, 1337, default));
}

test "apply applies no scaling to unsigned 0" {
    testing.expectEqual(0, apply(i16, 0, default * 2));
}

test "apply wraps signed values on overflow instead of trapping" {
    testing.expectEqual(63488, apply(u16, math.maxInt(u16), math.maxInt(Raw)));
}

test "apply wraps even full-width signed values on overflow instead of trapping" {
    testing.expectEqual(144115188075854848, apply(isize, math.maxInt(isize), math.maxInt(Raw)));
}

test "apply wraps even full-width unsigned values on overflow instead of trapping" {
    testing.expectEqual(288230376151710720, apply(usize, math.maxInt(usize), math.maxInt(Raw)));
}
