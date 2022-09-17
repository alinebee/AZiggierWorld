//! Utilities for fixed-precision interpolation of two integer values.

const std = @import("std");

pub const Ratio = u8;

/// Linearly interpolate between a start and end value using fixed precision integer math.
/// Ratio is the progress "through" the interpolation, from 0-255:
/// 0 returns the start value, and 255 returns the end value.
pub fn interpolate(comptime Int: type, start: Int, end: Int, ratio: Ratio) Int {
    const FullwidthInt = comptime if (std.meta.trait.isUnsignedInt(Int)) usize else isize;
    const max_ratio = comptime std.math.maxInt(Ratio);

    const start_weight = max_ratio - ratio;
    const end_weight = ratio;

    const weighted_start = @as(FullwidthInt, start) * start_weight;
    const weighted_end = @as(FullwidthInt, end) * end_weight;

    // The reference implementation divided by 256, but weights are between 0-255;
    // this caused interpolated values to be erroneously rounded down.
    const interpolated_value = @divTrunc(weighted_start + weighted_end, max_ratio);

    return @intCast(Int, interpolated_value);
}

// - interpolate tests -

const testing = @import("utils").testing;

// -- Unsigned interpolation --

test "interpolate returns unsigned start value when ratio is 0" {
    const interpolated_value = interpolate(u8, 100, 255, 0);
    try testing.expectEqual(100, interpolated_value);
}

test "interpolate returns unsigned end value when ratio is 255" {
    const interpolated_value = interpolate(u8, 100, 255, 255);
    try testing.expectEqual(255, interpolated_value);
}

test "interpolate returns unsigned interpolated value rounding down when ratio is midway" {
    const interpolated_value = interpolate(u8, 100, 255, 128);
    try testing.expectEqual(177, interpolated_value);
}

// -- Signed interpolation --

test "interpolate returns signed start value when ratio is 0" {
    const interpolated_value = interpolate(i8, -128, 127, 0);
    try testing.expectEqual(-128, interpolated_value);
}

test "interpolate returns signed end value when ratio is 255" {
    const interpolated_value = interpolate(i8, -128, 127, 255);
    try testing.expectEqual(127, interpolated_value);
}

test "interpolate returns signed interpolated value rounding down when ratio is midway" {
    const interpolated_value = interpolate(i8, -128, 127, 128);
    try testing.expectEqual(0, interpolated_value);
}
