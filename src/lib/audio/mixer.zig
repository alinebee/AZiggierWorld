const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const timing = anotherworld.timing;
const static_limits = anotherworld.static_limits;

/// A mixer that mixes the output of 4 channels into a single stream of 8-bit mono audio.
pub const Mixer = struct {
    /// The current state of each of the 4 channels.
    /// If null, nothing is playing on that channel.
    channels: [static_limits.channel_count]?ChannelState = .{null} ** static_limits.channel_count,

    const Self = @This();

    /// Play the specified sound on the specified channel,
    /// replacing any existing sound playing on that channel.
    pub fn play(self: *Self, sound: audio.SoundResource, channel_id: audio.ChannelID, frequency: timing.Hz, volume: audio.Volume) void {
        self.channels[channel_id.index()] = ChannelState{
            .sound = sound,
            .frequency = frequency,
            .volume = volume,
        };

        anotherworld.log.debug("Play channel #{}: sound #{*} (repeats: {}), frequency: {}, volume: {}", .{
            channel_id,
            sound.data,
            sound.loop_start != null,
            frequency,
            volume,
        });
    }

    /// Stop any sound playing on the specified channel.
    pub fn stop(self: *Self, channel_id: audio.ChannelID) void {
        self.channels[channel_id.index()] = null;

        anotherworld.log.debug("Stop channel #{}", .{channel_id});
    }

    /// Stop playing sound on all channels.
    pub fn stopAll(self: *Self) void {
        for (self.channels) |*channel| {
            channel.* = null;
        }
    }

    /// Populate an audio output buffer with sound data, sampled at the specified sample rate.
    pub fn mix(self: *Self, buffer: []u8, sample_rate: timing.Hz) void {
        each_channel: for (self.channels) |*channel| {
            if (channel.*) |*active_channel| {
                for (buffer) |*output| {
                    if (active_channel.sample(sample_rate)) |sample| {
                        // +| is Zig's saturating add operator
                        output.* +|= sample;
                    } else {
                        // If the channel reached the end, stop playing it immediately
                        channel.* = null;
                        break :each_channel;
                    }
                }
            }
        }
    }
};

const ChannelState = struct {
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

    /// Sample a single byte of audio data from the channel at the specified sample rate,
    /// advancing the cursor by the appropriate distance to get the next sample.
    /// Returns null if the channel has reached the end of non-looping sound data.
    fn sample(self: *ChannelState, sample_rate: timing.Hz) ?u8 {
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
        // TODO: use the FixedPrecision type to model this.

        // The fractional distance to advance the audio cursor by for each sampled byte:
        // a ratio of the sample rate and frequency.
        // TODO: precompute this like the reference implementation?
        const increment = (self.frequency << cursor_precision) / sample_rate;

        // Calculate how much to weight each byte of the interpolated result.
        const end_weight = self.cursor & cursor_fraction_mask;
        const start_weight = cursor_fraction_mask - end_weight;

        // Calculate which two bytes of the audio data to interpolate between.
        const start_byte = self.cursor >> cursor_precision;

        // FIXME: nothing in the reference algorithm seems to prove this precondition will be true;
        // it could become false with a pathological sample rate value.
        std.debug.assert(start_byte < self.sound.data.len);

        const end_byte = block: {
            const max_byte = self.sound.data.len - 1;

            if (start_byte < max_byte) {
                self.cursor += increment;
                break :block start_byte + 1;
            } else if (self.sound.loop_start) |loop_start| {
                // If we've reached the end of a looping sample,
                // rewind to the loop point and interpolate with that.
                //
                // The reference implementation appeared to have a bug:
                // it assigned the loop's start offset to its cursor directly,
                // but the loop start is a byte offset while the cursor is scaled.
                // This meant that sounds that looped midway would loop to a point
                // too early.
                //self.cursor = loop_start;
                self.cursor = loop_start * increment;
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
        const interpolated_value = ((start_value * start_weight) + (end_value * end_weight)) >> cursor_precision;

        // FIXME: Copypasta from reference implemnetation, but I'm not sure it's correct:
        // It should be using 63 as the divisor and not 64, because volume ranges from 0-63.
        const amplified_value = (interpolated_value * self.volume) / (static_limits.max_volume + 1);

        // Sure would be nice if Zig had a saturating equivalent to @truncate.
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
    testing.refAllDecls(Mixer);
}
