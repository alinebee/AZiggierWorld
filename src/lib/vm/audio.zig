const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const vm = anotherworld.vm;
const timing = anotherworld.timing;
const log = anotherworld.log;
const static_limits = anotherworld.static_limits;

/// The audio subsystem responsible for handling sound and music playback and sending audio data to the host's mixer.
pub const Audio = struct {
    /// The allocator used for initializing the audio buffer.
    allocator: std.mem.Allocator,

    /// The 4-channel mixer used for sampling and mixing audio from sound effects and music.
    mixer: audio.Mixer,

    /// The currently-playing music. Null if no music is playing.
    music_player: ?audio.MusicPlayer = null,

    /// The buffer used for storing processed audio before it is consumed by the host.
    buffer: []audio.Sample,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, sample_rate: timing.Hz) !Audio {
        const mixer = audio.Mixer{ .sample_rate = sample_rate };
        const buffer_size = mixer.bufferSize(static_limits.max_frame_duration);

        return Audio{
            .allocator = allocator,
            .mixer = mixer,
            .buffer = try allocator.alloc(audio.Sample, buffer_size),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
        self.* = undefined;
    }

    /// Start playing a music track from a specified resource.
    pub fn playMusic(self: *Self, music_data: []const u8, repository: anytype, timing_mode: timing.Timing, offset: audio.Offset, tempo: ?audio.Tempo) !void {
        const music = try audio.MusicResource.parse(music_data);
        self.music_player = try audio.MusicPlayer.init(music, repository, timing_mode, offset, tempo);

        log.debug("playMusic: play {*} at offset {} tempo {}", .{
            music_data,
            offset,
            tempo,
        });
    }

    /// Override the tempo of the current music track. Has no effect if no music is playing.
    pub fn setMusicTempo(self: *Self, tempo: audio.Tempo) !void {
        if (self.music_player) |*player| {
            try player.setTempo(tempo);
            log.debug("setMusicTempo: set tempo to {}", .{tempo});
        } else {
            log.debug("setMusicTempo: attempted to set tempo to {} while no music was playing", .{tempo});
        }
    }

    /// Stop playing any current music track. Any in-progress sounds will continue playing.
    pub fn stopMusic(self: *Self) void {
        self.music_player = null;
        log.debug("stopMusic: stop playing", .{});
    }

    /// Play a sound effect from the specified resource on the specified channel.
    pub fn playSound(self: *Self, sound_data: []const u8, channel_id: audio.ChannelID, volume: audio.Volume, frequency_id: audio.FrequencyID) !void {
        const sound = try audio.SoundResource.parse(sound_data);
        const frequency = frequency_id.frequency();
        self.mixer.play(sound, channel_id, frequency, volume);
    }

    /// Stop any sound effect playing on the specified channel.
    pub fn stopChannel(self: *Self, channel_id: audio.ChannelID) void {
        self.mixer.stop(channel_id);
    }

    /// Initialize and fill an 8-bit audio buffer with data for the specified length of time.
    /// Caller owns returned memory.
    /// Returns an error if a suitable buffer could not be allocated or sound playback failed.
    pub fn produceAudio(self: *Self, time: timing.Milliseconds, mark: *?audio.Mark) ProduceAudioError![]const audio.Sample {
        const bytes_needed = self.mixer.bufferSize(time);
        var filled_bytes = self.buffer[0..bytes_needed];

        if (self.music_player) |*music_player| {
            // If we're playing music, generate audio in increments of the music player's
            // own update rate: this ensures that song changes take effect on the mixer
            // at the right times in the audio playback.
            const time_chunk = music_player.ms_per_row;

            var time_consumed: vm.Milliseconds = 0;
            var chunk_start: usize = 0;
            while (time_consumed < time) : (time_consumed += time_chunk) {
                const time_remaining = @minimum(time_chunk, time - time_consumed);
                const chunk_length = self.mixer.bufferSize(time_remaining);
                const chunk_end = @minimum(chunk_start + chunk_length, bytes_needed);
                var chunk_buffer = filled_bytes[chunk_start..chunk_end];

                self.mixer.mix(chunk_buffer);
                music_player.playForDuration(&self.mixer, time_remaining, mark) catch |err| {
                    switch (err) {
                        error.EndOfTrack => {
                            self.music_player = null;
                            break;
                        },
                        else => return err,
                    }
                };
                chunk_start = chunk_end;
            }
        } else {
            // Otherwise, we can fill the whole buffer in a straight shot.
            self.mixer.mix(filled_bytes);
        }

        return filled_bytes;
    }

    pub const ProduceAudioError = audio.MusicPlayer.PlayError || std.mem.Allocator.Error;
};

// -- Tests --

const testing = @import("utils").testing;

test "Everything compiles" {
    testing.refAllDecls(Audio);
}
