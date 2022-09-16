const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const timing = anotherworld.timing;
const static_limits = anotherworld.static_limits;

const meta = @import("utils").meta;

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

        // Convert the cursor to a whole byte offset within the sound data and
        // a fractional offset to interpolate adjacent samples by.
        const whole_offset = @as(audio.SoundResource.Offset, self.cursor >> cursor_precision);
        const fractional_offset = @truncate(audio.SoundResource.FractionalOffset, self.cursor);

        // If the sample cursor is completely beyond the end of an unlooped sound,
        // play nothing and do not advance the cursor.
        const interpolated_sample = self.sound.interpolatedSampleAt(whole_offset, fractional_offset) orelse return null;

        // Scale the sample according to the volume.
        const scaled_sample = self.volume.applyTo(interpolated_sample);

        // Advance the cursor by the appropriate distance for the current frequency and sample rate.
        // TODO: prevent this from trapping when extremely large cursor values overflow.
        const increment = (self.frequency << cursor_precision) / sample_rate;
        self.cursor += increment;

        return scaled_sample;
    }

    // The number of bits of fractional precision in the cursor.
    const cursor_precision = meta.bitCount(audio.SoundResource.FractionalOffset);
};

// -- Tests --

const testing = @import("utils").testing;

fn expectSamples(comptime expected: []const ?audio.Sample, state: *ChannelState, sample_rate: timing.Hz) !void {
    var samples: [expected.len]?audio.Sample = undefined;

    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }

    try testing.expectEqualSlices(?audio.Sample, expected, &samples);
}

test "Everything compiles" {
    testing.refAllDecls(ChannelState);
}

// - Unlooped sample tests -

test "sample returns interpolated data until end of unlooped sound is reached" {
    var state = ChannelState{
        .sound = .{
            .data = &[_]audio.Sample{ 0, 4, 8, 12, 16 },
            .loop_start = null,
        },
        .frequency = 11025,
        .volume = audio.Volume.cast(63),
    };
    const sample_rate = 22050;
    const expected_samples = [11]?audio.Sample{ 0, 2, 4, 6, 8, 10, 12, 14, 16, 7, null };

    try expectSamples(&expected_samples, &state, sample_rate);
}

test "sample returns uninterpolated bytes until end of unlooped sound is reached when output sample rate matches sound frequency" {
    var state = ChannelState{
        .sound = .{
            .data = &[_]audio.Sample{ 0, 4, 8, 12, 16 },
            .loop_start = null,
        },
        .frequency = 22050,
        .volume = audio.Volume.cast(63),
    };
    const sample_rate = 22050;
    const expected_samples = [6]?audio.Sample{ 0, 4, 8, 12, 16, null };

    try expectSamples(&expected_samples, &state, sample_rate);
}

test "sample jumps over bytes until end of unlooped sound is reached when sound frequency is higher than output sample rate" {
    var state = ChannelState{
        .sound = .{
            .data = &[_]audio.Sample{ 0, 4, 8, 12, 16 },
            .loop_start = null,
        },
        .frequency = 44100,
        .volume = audio.Volume.cast(63),
    };
    const sample_rate = 22050;
    const expected_samples = [4]?audio.Sample{ 0, 8, 16, null };

    try expectSamples(&expected_samples, &state, sample_rate);
}

// - Looped sample tests -

test "sample interpolates between last data and loop point for looped sample" {
    var state = ChannelState{
        .sound = .{
            .data = &[_]audio.Sample{ 0, 4, 8, 12, 16 },
            .loop_start = 2,
        },
        .frequency = 11025,
        .volume = audio.Volume.cast(63),
    };
    const sample_rate = 22050;
    const expected_samples = [16]?audio.Sample{ 0, 2, 4, 6, 8, 10, 12, 14, 16, 11, 8, 10, 12, 14, 16, 11 };

    try expectSamples(&expected_samples, &state, sample_rate);
}

test "sample loops with uninterpolated bytes when output sample rate matches sound frequency on looped sample" {
    var state = ChannelState{
        .sound = .{
            .data = &[_]audio.Sample{ 0, 4, 8, 12, 16 },
            .loop_start = 2,
        },
        .frequency = 22050,
        .volume = audio.Volume.cast(63),
    };
    const sample_rate = 22050;
    const expected_samples = [12]?audio.Sample{ 0, 4, 8, 12, 16, 8, 12, 16, 8, 12, 16, 8 };

    try expectSamples(&expected_samples, &state, sample_rate);
}

test "sample loops jumps over bytes when output sample rate matches sound frequency on looped sample" {
    var state = ChannelState{
        .sound = .{
            .data = &[_]audio.Sample{ 0, 4, 8, 12, 16 },
            .loop_start = 2,
        },
        .frequency = 44100,
        .volume = audio.Volume.cast(63),
    };
    const sample_rate = 22050;
    const expected_samples = [10]?audio.Sample{ 0, 8, 16, 12, 8, 16, 12, 8, 16, 12 };

    try expectSamples(&expected_samples, &state, sample_rate);
}

// - Volume tests -

test "sample scales values by volume" {
    var state = ChannelState{
        .sound = .{
            .data = &[_]audio.Sample{ 0, 4, 8, 12, 16 },
            .loop_start = null,
        },
        .frequency = 11025,
        .volume = audio.Volume.cast(32),
    };
    const sample_rate = 22050;
    const expected_samples = [11]?audio.Sample{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 3, null };

    try expectSamples(&expected_samples, &state, sample_rate);
}

test "samples played at 0 volume are silent" {
    var state = ChannelState{
        .sound = .{
            .data = &[_]audio.Sample{ 0, 4, 8, 12, 16 },
            .loop_start = null,
        },
        .frequency = 11025,
        .volume = audio.Volume.cast(0),
    };
    const sample_rate = 22050;
    const expected_samples = [11]?audio.Sample{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, null };

    try expectSamples(&expected_samples, &state, sample_rate);
}

// - Misc tests -

test "sample does not overflow when cursor goes beyond the end of looping sound data" {
    var state = ChannelState{
        .sound = .{
            .data = &[_]audio.Sample{ 0, 4, 8, 12, 16 },
            .loop_start = 2,
        },
        .frequency = 22050,
        .volume = audio.Volume.cast(63),
    };
    const sample_rate = 8000; // Results in cursor jumping by over 2 bytes each sample

    var samples: [10]?audio.Sample = undefined;
    for (samples) |*sample| {
        sample.* = state.sample(sample_rate);
    }
}
