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
    // The reference implementation implicitly relies on C++'s integral promotion rules:
    // https://en.cppreference.com/w/cpp/language/implicit_conversion#Numeric_promotions
    // where signed 16-bit values would be silently promoted to native-width integers
    // before doing arithmetic, then truncated after.
    // Zig does not automatically do this (for good reason) and would give inconsistent
    // results to C/C++ if we naively adapted the original algorithm.
    // Instead, we explicitly promote to full-width to document what's going on and ensure
    // we match the same behaviour.
    //
    // This implementation may diverge from the original game's behaviour on 16-bit hardware,
    // in cases where the raw scale value was large enough to flow into the sign bit of an i16;
    // that could theoretically happen since scale values from registers are 16 bits,
    // but I expect that it never occurred in the original game.
    const FullwidthInt = comptime if (trait.isUnsignedInt(Int)) usize else isize;
    const fullwidth_divisor = @as(FullwidthInt, default);
    const fullwidth_value = @as(FullwidthInt, value);
    const fullwidth_scale = @as(FullwidthInt, scale);
    const fullwidth_scaled_value = @divTrunc(fullwidth_value *% fullwidth_scale, fullwidth_divisor);

    return @truncate(Int, fullwidth_scaled_value);
}

// -- Tests --

const testing = @import("../utils/testing.zig");
const math = @import("std").math;

test "apply scales up signed values" {
    try testing.expectEqual(-2674, apply(i16, -1337, default * 2));
}

test "apply scales down signed values, rounding down" {
    try testing.expectEqual(-668, apply(i16, -1337, default / 2));
}

test "apply applies no scaling to signed values at default value" {
    try testing.expectEqual(-1337, apply(i16, -1337, default));
}

test "apply applies no scaling to signed 0" {
    try testing.expectEqual(0, apply(i16, 0, default * 2));
}

test "apply with scale 0 scales down to 0" {
    try testing.expectEqual(0, apply(i16, 1337, 0));
    try testing.expectEqual(0, apply(i16, -1337, 0));
}

test "apply wraps signed values on overflow instead of trapping" {
    try testing.expectEqual(-1536, apply(i16, math.maxInt(i16), math.maxInt(Raw)));
}

test "apply wraps signed values on underflow instead of trapping" {
    try testing.expectEqual(512, apply(i16, math.minInt(i16), math.maxInt(Raw)));
}

test "apply scales up unsigned values" {
    try testing.expectEqual(2674, apply(u16, 1337, default * 2));
}

test "apply scales down unsigned values, rounding down" {
    try testing.expectEqual(668, apply(u16, 1337, default / 2));
}

test "apply applies no scaling to unsigned values at default value" {
    try testing.expectEqual(1337, apply(u16, 1337, default));
}

test "apply applies no scaling to unsigned 0" {
    try testing.expectEqual(0, apply(i16, 0, default * 2));
}

test "apply wraps signed values on overflow instead of trapping" {
    try testing.expectEqual(63488, apply(u16, math.maxInt(u16), math.maxInt(Raw)));
}

test "apply wraps even full-width signed values on overflow instead of trapping" {
    try testing.expectEqual(144115188075854848, apply(isize, math.maxInt(isize), math.maxInt(Raw)));
}

test "apply wraps even full-width unsigned values on overflow instead of trapping" {
    try testing.expectEqual(288230376151710720, apply(usize, math.maxInt(usize), math.maxInt(Raw)));
}
