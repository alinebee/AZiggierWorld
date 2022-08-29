const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const vm = anotherworld.vm;
const log = anotherworld.log;

/// The audio subsystem responsible for handling sound and music playback and sending audio data to the host's mixer.
pub const Audio = struct {
    music_delay: audio.Delay = 0,

    const Self = @This();

    /// Start playing a music track from a specified resource.
    pub fn playMusic(_: *Self, music_data: []const u8, offset: audio.Offset, delay: audio.Delay) !void {
        const music = try audio.MusicResource.parse(music_data);

        log.debug("playMusic: play {*} at offset {} after delay {} (sequence length: {})", .{
            music_data,
            offset,
            delay,

            music.sequence().len,
        });
    }

    /// Set a delay on the current or subsequent music track.
    pub fn setMusicDelay(self: *Self, delay: audio.Delay) void {
        self.music_delay = delay;
        log.debug("setMusicDelay: set delay to {}", .{delay});
    }

    /// Stop playing any current music track.
    pub fn stopMusic(_: *Self) void {
        log.debug("stopMusic: stop playing", .{});
    }

    /// Play a sound effect from the specified resource on the specified channel.
    pub fn playSound(_: *Self, sound_data: []const u8, channel_id: vm.ChannelID, volume: audio.Volume.Trusted, frequency_id: audio.FrequencyID) !void {
        const sound = try audio.SoundResource.parse(sound_data);

        log.debug("playSound: play {*} on channel {} at volume {}, frequency {} (has intro: {}, loops: {})", .{
            sound_data,
            channel_id,
            volume,
            frequency_id,
            sound.intro != null,
            sound.loop != null,
        });
    }

    /// Stop any sound effect playing on the specified channel.
    pub fn stopChannel(_: *Self, channel_id: vm.ChannelID) void {
        log.debug("stopChannel: stop playing on channel {}", .{channel_id});
    }
};
