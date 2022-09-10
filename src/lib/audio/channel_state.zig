const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const timing = anotherworld.timing;
const static_limits = anotherworld.static_limits;

pub const ChannelState = struct {
    /// The sound data being played on this channel.
    sound: audio.SoundResource,
    /// The frequency in Hz at which to play this sound.
    frequency: timing.Hz,
    /// The volume at which to play this sound.
    volume: audio.Volume,
    /// The current cursor offset within the sound's data.
    /// This is a fixed-point value with 8 bits of fractional precision:
    /// divide by 256 to arrive at the actual byte offset within the audio data.
    cursor: usize = 0,

    /// Sample a single byte of audio data from the channel at current cursor
    /// and the specified sample rate, and advances the cursor by an appropriate
    /// distance for the specified sample rate so that the next call to `sample`
    /// will get the next sample for that rate.
    /// Returns null and does not advance the cursor if the channel has reached
    /// the end of non-looping sound data.
    pub fn sample(self: *ChannelState, sample_rate: timing.Hz) ?u8 {
        std.debug.assert(sample_rate > 0);

        // Implementation note:
        // The difference between the sound's playback frequency and the output sample rate
        // means that the sampling will almost never fall on byte boundaries.
        // Instead, this function needs to sample "in between" each byte by linearly
        // interpolating two adjacent bytes of audio data, weighted according to how far
        // through the byte the sampling cursor has gotten.
        //
        // Nowadays, linear interpolation is a simple floating-point operation.
        // But the reference implementation avoided floating-point arithmetic by storing
        // the sampling cursor as a fixed-point value with 8 bits of precision.
        // It scaled all whole values up by 256, interpolated using a ratio from 0-255
        // (instead of 0.0-1.0), and then scaled values back down by 256 after the
        // fixed-point math was done.
        // We do the same here to stay faithful to the original game's output.
        //
        // TODO: use the FixedPrecision type to model this?

        // Calculate how much to weight each byte of the interpolated result.
        const end_weight = self.cursor & cursor_fraction_mask;
        const start_weight = cursor_fraction_mask - end_weight;

        // Calculate which two bytes of the audio data to interpolate between.
        const start_byte = self.cursor >> cursor_precision;

        // FIXME: nothing in the reference algorithm proves this precondition will be true;
        // it will become false with a pathological sample rate value. To be safe, looped sounds
        // should modulo-wrap overflowing start and end byte offsets back around to the loop point.
        // (To be fully correct we should also preserve the fractional part of the cursor
        // when wrapping; though this would probably diverge from the original game's behaviour.)
        std.debug.assert(start_byte < self.sound.data.len);

        const end_byte = block: {
            const max_byte = self.sound.data.len - 1;

            if (start_byte < max_byte) {
                // The fractional distance to advance the audio cursor by for each sampled byte:
                // a ratio of the sample rate and frequency.
                // TODO: precompute this like the reference implementation?
                const increment = (self.frequency << cursor_precision) / sample_rate;

                self.cursor += increment;
                break :block start_byte + 1;
            } else if (self.sound.loop_start) |loop_start| {
                // If we've reached the end of a looping sample,
                // rewind to the loop point and interpolate with that.
                //
                // The reference implementation appeared to have a bug:
                // it assigned the loop's start offset to its cursor directly,
                // but the loop start is a byte offset while the cursor is scaled.
                // This meant that sounds which should have looped midway through
                // the sample would loop to a point very close to the start.
                //self.cursor = loop_start;
                self.cursor = loop_start << cursor_precision;
                break :block loop_start;
            } else {
                // If we've reached the end of a non-looping sample,
                // stop playing this channel.
                return null;
            }
        };

        // Linearly interpolate between the values at the two offsets
        const start_value = @as(usize, self.sound.data[start_byte]);
        const end_value = @as(usize, self.sound.data[end_byte]);
        // The reference implementation divided by 256, but weights are between 0-255;
        // this caused interpolated values to be erroneously rounded down.
        const interpolated_value = ((start_value * start_weight) + (end_value * end_weight)) / cursor_fraction_mask;

        // Reference implementation divider by 64 but that resulted in never playing a sound
        // at full volume. Volume ranges from 0-63; dividing by 63 gives the full range.
        const amplified_value = (interpolated_value * self.volume) / static_limits.max_volume;

        // Sure would be nice if Zig had a saturating equivalent of @truncate.
        return std.math.min(amplified_value, @as(u8, std.math.maxInt(u8)));
    }

    // The number of bits of fractional precision in the cursor.
    const cursor_precision = 8;
    // The bits of the cursor that represent the fractional component.
    const cursor_fraction_mask = (1 << cursor_precision) - 1;
};

// -- Tests --

const testing = @import("utils").testing;

test "Everything compiles" {
    testing.refAllDecls(ChannelState);
}

const raw_sound_data = [_]u8{ 0, 4, 8, 12, 16 };

test "sample returns interpolated data until end of unlooped sound is reached" {
    var state = ChannelState{
        .sound = .{
            .data = &raw_sound_data,
            .loop_start = null,
        },
        .frequency = 11025,
        .volume = 63,
    };
    const sample_rate = 22050;

    var samples: [10]?u8 = undefined;
    // FIXME: the second-to-last sample should be 16. We still follow the reference implementation,
    // which bails out as soon as it reaches the last byte even if no interpolation needs to be done.
    const expected_samples = [10]?u8{ 0, 2, 4, 6, 8, 10, 12, 14, null, null };

    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }
    try testing.expectEqualSlices(?u8, &expected_samples, &samples);
}

test "sample returns uninterpolated bytes when output sample rate matches sound frequency" {
    var state = ChannelState{
        .sound = .{
            .data = &raw_sound_data,
            .loop_start = null,
        },
        .frequency = 22050,
        .volume = 63,
    };
    const sample_rate = 22050;

    var samples: [6]?u8 = undefined;
    // FIXME: the second-to-last sample should be 16. We still follow the reference implementation,
    // which bails out as soon as it reaches the last byte even if no interpolation needs to be done.
    const expected_samples = [6]?u8{ 0, 4, 8, 12, null, null };

    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }
    try testing.expectEqualSlices(?u8, &expected_samples, &samples);
}

test "sample skips over bytes when sound frequency is higher than output sample rate" {
    var state = ChannelState{
        .sound = .{
            .data = &raw_sound_data,
            .loop_start = null,
        },
        .frequency = 44100,
        .volume = 63,
    };
    const sample_rate = 22050;

    var samples: [4]?u8 = undefined;
    // FIXME: the second-to-last sample should be 16. We still follow the reference implementation,
    // which bails out as soon as it reaches the last byte even if no interpolation needs to be done.
    const expected_samples = [4]?u8{ 0, 8, null, null };

    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }
    try testing.expectEqualSlices(?u8, &expected_samples, &samples);
}

test "sample interpolates between last data and loop point for looped sample" {
    var state = ChannelState{
        .sound = .{
            .data = &raw_sound_data,
            .loop_start = 2,
        },
        .frequency = 11025,
        .volume = 63,
    };
    const sample_rate = 22050;

    var samples: [10]?u8 = undefined;
    // FIXME: the final value should be 12: 16 interpolated with 8.
    // We still follow the reference implementation, which resets the cursor to the start
    // of the byte when looping instead of allowing it to fall midway.
    const expected_samples = [10]?u8{ 0, 2, 4, 6, 8, 10, 12, 14, 16, 8 };

    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }
    try testing.expectEqualSlices(?u8, &expected_samples, &samples);
}

test "sample does not overflow when cursor goes beyond the end of looping sound data" {
    // This test will currently crash: we still follow the reference implementation,
    // which did insufficient bounds checking and could seek beyond the end of sound data
    // if the sample rate caused entire bytes to be skipped.
    return error.SkipZigTest;

    // var state = ChannelState{
    //     .sound = .{
    //         .data = &raw_sound_data,
    //         .loop_start = 2,
    //     },
    //     .frequency = 22050,
    //     .volume = 63,
    // };
    // const sample_rate = 8000;

    // var samples: [10]?u8 = undefined;
    // for (samples) |*sample| {
    //     sample.* = state.sample(sample_rate);
    // }
}

test "sample scales values by volume" {
    var state = ChannelState{
        .sound = .{
            .data = &raw_sound_data,
            .loop_start = null,
        },
        .frequency = 11025,
        .volume = 32,
    };
    const sample_rate = 22050;

    var samples: [10]?u8 = undefined;
    // FIXME: the second-to-last sample should be 8. We still follow the reference implementation,
    // which bails out as soon as it reaches the last byte even if no interpolation needs to be done.
    const expected_samples = [10]?u8{ 0, 1, 2, 3, 4, 5, 6, 7, null, null };

    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }
    try testing.expectEqualSlices(?u8, &expected_samples, &samples);
}
