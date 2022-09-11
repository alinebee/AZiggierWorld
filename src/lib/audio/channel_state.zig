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
    pub fn sample(self: *ChannelState, sample_rate: timing.Hz) ?audio.Sample {
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
        const ratio = @truncate(Ratio, self.cursor);

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

        const start_sample = self.sound.data[start_byte];
        const end_sample = self.sound.data[end_byte];
        const interpolated_sample = interpolate(audio.Sample, start_sample, end_sample, ratio);

        return self.volume.applyTo(interpolated_sample);
    }

    // The number of bits of fractional precision in the cursor.
    const cursor_precision = 8;
};

const Ratio = u8;
/// Linearly interpolate between a start and end value using fixed precision integer math.
/// Ratio is the progress "through" the interpolation, from 0-255:
/// 0 returns the start value, and 255 returns the end value.
fn interpolate(comptime Int: type, start: Int, end: Int, ratio: Ratio) Int {
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

// -- Tests --

const testing = @import("utils").testing;

test "Everything compiles" {
    testing.refAllDecls(ChannelState);
}

const raw_sound_data = [_]audio.Sample{ 0, 4, 8, 12, 16 };

// - fixedPrecisionLerp tests -

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

// - Sample tests -

test "sample returns interpolated data until end of unlooped sound is reached" {
    var state = ChannelState{
        .sound = .{
            .data = &raw_sound_data,
            .loop_start = null,
        },
        .frequency = 11025,
        .volume = audio.Volume.cast(63),
    };
    const sample_rate = 22050;

    var samples: [10]?audio.Sample = undefined;
    // FIXME: the second-to-last sample should be 16. We still follow the reference implementation,
    // which bails out as soon as it reaches the last byte even if no interpolation needs to be done.
    const expected_samples = [10]?audio.Sample{ 0, 2, 4, 6, 8, 10, 12, 14, null, null };

    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }
    try testing.expectEqualSlices(?audio.Sample, &expected_samples, &samples);
}

test "sample returns uninterpolated bytes when output sample rate matches sound frequency" {
    var state = ChannelState{
        .sound = .{
            .data = &raw_sound_data,
            .loop_start = null,
        },
        .frequency = 22050,
        .volume = audio.Volume.cast(63),
    };
    const sample_rate = 22050;

    var samples: [6]?audio.Sample = undefined;
    // FIXME: the second-to-last sample should be 16. We still follow the reference implementation,
    // which bails out as soon as it reaches the last byte even if no interpolation needs to be done.
    const expected_samples = [6]?audio.Sample{ 0, 4, 8, 12, null, null };

    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }
    try testing.expectEqualSlices(?audio.Sample, &expected_samples, &samples);
}

test "sample skips over bytes when sound frequency is higher than output sample rate" {
    var state = ChannelState{
        .sound = .{
            .data = &raw_sound_data,
            .loop_start = null,
        },
        .frequency = 44100,
        .volume = audio.Volume.cast(63),
    };
    const sample_rate = 22050;

    var samples: [4]?audio.Sample = undefined;
    // FIXME: the second-to-last sample should be 16. We still follow the reference implementation,
    // which bails out as soon as it reaches the last byte even if no interpolation needs to be done.
    const expected_samples = [4]?audio.Sample{ 0, 8, null, null };

    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }
    try testing.expectEqualSlices(?audio.Sample, &expected_samples, &samples);
}

test "sample interpolates between last data and loop point for looped sample" {
    var state = ChannelState{
        .sound = .{
            .data = &raw_sound_data,
            .loop_start = 2,
        },
        .frequency = 11025,
        .volume = audio.Volume.cast(63),
    };
    const sample_rate = 22050;

    var samples: [10]?audio.Sample = undefined;
    // FIXME: the final value should be 12: 16 interpolated with 8.
    // We still follow the reference implementation, which resets the cursor to the start
    // of the byte when looping instead of allowing it to fall midway.
    const expected_samples = [10]?audio.Sample{ 0, 2, 4, 6, 8, 10, 12, 14, 16, 8 };

    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }
    try testing.expectEqualSlices(?audio.Sample, &expected_samples, &samples);
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
    //     .volume = audio.Volume.cast(63),
    // };
    // const sample_rate = 8000;

    // var samples: [10]?audio.Sample = undefined;
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
        .volume = audio.Volume.cast(32),
    };
    const sample_rate = 22050;

    var samples: [10]?audio.Sample = undefined;
    // FIXME: the second-to-last sample should be 8. We still follow the reference implementation,
    // which bails out as soon as it reaches the last byte even if no interpolation needs to be done.
    const expected_samples = [10]?audio.Sample{ 0, 1, 2, 3, 4, 5, 6, 7, null, null };

    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }
    try testing.expectEqualSlices(?audio.Sample, &expected_samples, &samples);
}
