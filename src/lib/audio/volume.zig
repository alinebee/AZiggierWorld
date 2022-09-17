const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const static_limits = anotherworld.static_limits;

const intToEnum = @import("utils").meta.intToEnum;
const saturatingCast = @import("utils").meta.saturatingCast;

const Clamped = u6;

/// The volume at which to play a sound effect or note in a music track, as a value clamped to 0-63.
/// Guaranteed to be valid at compile time.
pub const Volume = enum(Clamped) {
    zero = 0,
    // Allow any value between 0-63.
    _,

    /// A raw volume as represented in Another World bytecode.
    /// Another World music instrument data represents volumes as 16-bit integers instead:
    /// see instrument.zig.
    pub const Raw = u8;

    /// An adjustment value to apply to a volume, from -128 to 127.
    pub const Delta = i8;

    const Self = @This();

    /// Convert a raw value from Another World bytecode or music data into a clamped volume.
    pub fn cast(raw: anytype) Self {
        const clamped_raw = saturatingCast(Clamped, raw);
        return @intToEnum(Volume, clamped_raw);
    }

    /// Ramp the specified volume by the specified volume delta.
    pub fn rampedBy(self: Self, delta: Delta) Self {
        const raw_volume: isize = @enumToInt(self);
        const scaled_volume = raw_volume +| delta;
        const clamped_volume = saturatingCast(Clamped, scaled_volume);
        return Volume.cast(clamped_volume);
    }

    /// Scale the specified audio sample value by this volume.
    pub fn applyTo(self: Self, sample: audio.Sample) audio.Sample {
        const fullwidth_sample = @as(isize, sample);

        // Reference implementation divider by 64 but that resulted in never playing a sound
        // at full volume. Volume ranges from 0-63; dividing by 63 gives the full range.
        const amplified_sample = @divTrunc(fullwidth_sample * @enumToInt(self), static_limits.max_volume);

        return saturatingCast(audio.Sample, amplified_sample);
    }
};

// -- Tests --

const testing = @import("utils").testing;

test "Clamped type matches range of legal volumes" {
    try static_limits.validateTrustedType(Clamped, static_limits.max_volume + 1);
}

test "parse returns Volume for in-range values" {
    try testing.expectEqual(@intToEnum(Volume, 0), Volume.cast(0));
    try testing.expectEqual(@intToEnum(Volume, 63), Volume.cast(static_limits.max_volume));
}

test "parse clamps out-of-range values" {
    try testing.expectEqual(@intToEnum(Volume, 63), Volume.cast(static_limits.max_volume + 1));
    try testing.expectEqual(@intToEnum(Volume, 63), Volume.cast(65535));
}
