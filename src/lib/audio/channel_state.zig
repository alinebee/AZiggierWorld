const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const timing = anotherworld.timing;
const static_limits = anotherworld.static_limits;

const meta = @import("utils").meta;

/// The current sound playback state of a channel in a mixer.
pub const ChannelState = struct {
    /// The sound data being played on this channel.
    sound: audio.SoundResource,
    /// The volume at which to play this sound.
    volume: audio.Volume,
    /// The amount to advance the cursor by after each sample.
    /// Calculated from the desired frequency of the sound and the global sample rate.
    increment: usize,
    /// The current cursor offset within the sound's data.
    /// This is a fixed-point value with 8 bits of fractional precision:
    /// divide by 256 to arrive at the actual byte offset within the audio data.
    cursor: usize = 0,

    pub fn init(sound: audio.SoundResource, frequency: timing.Hz, sample_rate: timing.Hz, volume: audio.Volume) ChannelState {
        // TODO 0.11+: replace with a ranged integer type once they're available:
        // https://github.com/ziglang/zig/issues/3806
        std.debug.assert(sample_rate > 0);

        const increment = (frequency << cursor_precision) / sample_rate;

        return .{
            .sound = sound,
            .volume = volume,
            .increment = increment,
        };
    }

    /// Samples a single byte of audio data from the channel at current cursor
    /// and the specified sample rate, and advances the cursor by an appropriate
    /// distance for the specified sample rate so that the next call to `sample`
    /// will get the next sample for that rate.
    /// Returns `null` and does not advance the cursor if the channel has reached
    /// the end of non-looping sound data.
    pub fn sample(self: *ChannelState) ?audio.Sample {
        // Convert the cursor to a whole byte offset within the sound data and
        // a fractional offset to interpolate adjacent samples by.
        const whole_offset = @as(audio.SoundResource.Offset, self.cursor >> cursor_precision);
        const fractional_offset = @truncate(audio.SoundResource.FractionalOffset, self.cursor);

        // If the sample cursor is completely beyond the end of an unlooped sound,
        // play nothing and do not advance the cursor.
        const interpolated_sample = self.sound.interpolatedSampleAt(whole_offset, fractional_offset) orelse return null;

        // Scale the sample according to the volume.
        const scaled_sample = self.volume.applyTo(interpolated_sample);

        // Advance the cursor by the appropriate distance for the frequency and sample rate.
        // TODO: prevent this from trapping when extremely large cursor values overflow.
        self.cursor += self.increment;

        return scaled_sample;
    }

    // The number of bits of fractional precision in the cursor.
    const cursor_precision = meta.bitCount(audio.SoundResource.FractionalOffset);
};

// -- Tests --

const testing = @import("utils").testing;

fn expectSamples(comptime expected: []const ?audio.Sample, state: *ChannelState) !void {
    var samples: [expected.len]?audio.Sample = undefined;

    for (samples) |*sample| {
        sample.* = state.sample();
    }

    try testing.expectEqualSlices(?audio.Sample, expected, &samples);
}

test "Everything compiles" {
    testing.refAllDecls(ChannelState);
}

// - Unlooped sound tests -

test "sample returns interpolated data until end of unlooped sound is reached" {
    var state = ChannelState.init(
        audio.SoundResource.init(&[_]audio.Sample{ 0, -4, 8, -12, 16 }, null),
        11025,
        22050,
        audio.Volume.cast(63),
    );
    const expected_samples = [11]?audio.Sample{ 0, -2, -4, 2, 8, -2, -12, 2, 16, 16, null };

    try expectSamples(&expected_samples, &state);
}

test "sample returns uninterpolated bytes until end of unlooped sound is reached when output sample rate matches sound frequency" {
    var state = ChannelState.init(
        audio.SoundResource.init(&[_]audio.Sample{ 0, -4, 8, -12, 16 }, null),
        22050,
        22050,
        audio.Volume.cast(63),
    );
    const expected_samples = [6]?audio.Sample{ 0, -4, 8, -12, 16, null };

    try expectSamples(&expected_samples, &state);
}

test "sample jumps over bytes until end of unlooped sound is reached when sound frequency is higher than output sample rate" {
    var state = ChannelState.init(
        audio.SoundResource.init(&[_]audio.Sample{ 0, -4, 8, -12, 16 }, null),
        44100,
        22050,
        audio.Volume.cast(63),
    );
    const expected_samples = [4]?audio.Sample{ 0, 8, 16, null };

    try expectSamples(&expected_samples, &state);
}

// - Looped sound tests -

test "sample interpolates between last data and loop point for looped sound" {
    var state = ChannelState.init(
        audio.SoundResource.init(&[_]audio.Sample{ 0, -4, 8, -12, 16 }, 2),
        11025,
        22050,
        audio.Volume.cast(63),
    );
    const expected_samples = [16]?audio.Sample{ 0, -2, -4, 2, 8, -2, -12, 2, 16, 11, 8, -2, -12, 2, 16, 11 };

    try expectSamples(&expected_samples, &state);
}

test "sample loops with uninterpolated bytes when output sample rate matches sound frequency on looped sound" {
    var state = ChannelState.init(
        audio.SoundResource.init(&[_]audio.Sample{ 0, -4, 8, -12, 16 }, 2),
        22050,
        22050,
        audio.Volume.cast(63),
    );
    const expected_samples = [12]?audio.Sample{ 0, -4, 8, -12, 16, 8, -12, 16, 8, -12, 16, 8 };

    try expectSamples(&expected_samples, &state);
}

test "sample loops jumps over bytes when output sample rate matches sound frequency on looped sound" {
    var state = ChannelState.init(
        audio.SoundResource.init(&[_]audio.Sample{ 0, -4, 8, -12, 16 }, 2),
        44100,
        22050,
        audio.Volume.cast(63),
    );
    const expected_samples = [10]?audio.Sample{ 0, 8, 16, -12, 8, 16, -12, 8, 16, -12 };

    try expectSamples(&expected_samples, &state);
}

// - Volume tests -

test "sample scales values by volume" {
    var state = ChannelState.init(
        audio.SoundResource.init(&[_]audio.Sample{ 0, -4, 8, -12, 16 }, null),
        11025,
        22050,
        audio.Volume.cast(32),
    );
    const expected_samples = [11]?audio.Sample{ 0, -1, -2, 1, 4, -1, -6, 1, 8, 8, null };

    try expectSamples(&expected_samples, &state);
}

test "samples played at 0 volume are scaled to 0" {
    var state = ChannelState.init(
        audio.SoundResource.init(&[_]audio.Sample{ 0, -4, 8, -12, 16 }, null),
        11025,
        22050,
        audio.Volume.cast(0),
    );
    const expected_samples = [11]?audio.Sample{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, null };

    try expectSamples(&expected_samples, &state);
}

// - Misc tests -

test "sample does not overflow when cursor goes beyond the end of looping sound data" {
    var state = ChannelState.init(
        audio.SoundResource.init(&[_]audio.Sample{ 0, -4, 8, -12, 16 }, 2),
        22050,
        8000, // Results in cursor jumping by over 2 bytes each sample
        audio.Volume.cast(63),
    );

    var samples: [10]?audio.Sample = undefined;
    for (samples) |*sample| {
        sample.* = state.sample();
    }
}
