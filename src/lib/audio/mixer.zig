const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const timing = anotherworld.timing;
const static_limits = anotherworld.static_limits;

const ChannelState = @import("channel_state.zig").ChannelState;

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

    /// Calculate the appropriate size in bytes for an audio buffer that covers
    /// the specified length of time, when sampled at the specified rate.
    pub fn bufferSize(time: timing.Milliseconds, sample_rate: timing.Hz) usize {
        return (time * sample_rate) / std.time.ms_per_s;
    }

    /// Populate an audio output buffer with sound data, sampled at the specified sample rate.
    /// This advances the currently-playing samples on each channel.
    pub fn mix(self: *Self, buffer: []u8, sample_rate: timing.Hz) void {
        each_channel: for (self.channels) |*channel| {
            if (channel.*) |*active_channel| {
                for (buffer) |*output| {
                    if (active_channel.sample(sample_rate)) |sample| {
                        // Use saturating add to clamp mixed samples to 0-255.
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

// -- Tests --

const testing = @import("utils").testing;

test "Everything compiles" {
    testing.refAllDecls(Mixer);
}
