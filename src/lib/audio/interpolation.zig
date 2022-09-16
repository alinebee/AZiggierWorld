//! Utilities for fixed-precision interpolation of two integer values.

const std = @import("std");

pub const Ratio = u8;

/// Linearly interpolate between a start and end value using fixed precision integer math.
/// Ratio is the progress "through" the interpolation, from 0-255:
/// 0 returns the start value, and 255 returns the end value.
pub fn interpolate(comptime Int: type, start: Int, end: Int, ratio: Ratio) Int {
    const max_ratio = comptime std.math.maxInt(Ratio);

    const start_weight = max_ratio - ratio;
    const end_weight = ratio;

    const weighted_start = @as(usize, start) * start_weight;
    const weighted_end = @as(usize, end) * end_weight;

    // The reference implementation divided by 256, but weights are between 0-255;
    // this caused interpolated values to be erroneously rounded down.
    const interpolated_value = (weighted_start + weighted_end) / max_ratio;

    return @intCast(Int, interpolated_value);
}

// - interpolate tests -

const testing = @import("utils").testing;

test "interpolate returns start value when ratio is 0" {
    const interpolated_value = interpolate(u8, 100, 255, 0);
    try testing.expectEqual(100, interpolated_value);
}

test "interpolate returns end value when ratio is 255" {
    const interpolated_value = interpolate(u8, 100, 255, 255);
    try testing.expectEqual(255, interpolated_value);
}

test "interpolate returns interpolated value rounding down when ratio is midway" {
    const interpolated_value = interpolate(u16, 100, 255, 127);
    try testing.expectEqual(177, interpolated_value);
}
