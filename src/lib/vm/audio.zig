const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const vm = anotherworld.vm;
const log = anotherworld.log;

/// The audio subsystem responsible for handling sound and music playback and sending audio data to the host's mixer.
pub const Audio = struct {
    /// The currently-playing music. Null if no music is playing.
    music_player: ?audio.MusicPlayer = null,

    const Self = @This();

    /// Start playing a music track from a specified resource.
    pub fn playMusic(_: *Self, music_data: []const u8, offset: audio.Offset, tempo: ?audio.Tempo) !void {
        _ = try audio.MusicResource.parse(music_data);

        log.debug("playMusic: play {*} at offset {} tempo {}", .{
            music_data,
            offset,
            tempo,
        });
    }

    /// Override the tempo of the current music track. Has no effect if no music is playing.
    pub fn setMusicTempo(_: *Self, tempo: audio.Tempo) void {
        log.debug("setMusicTempo: set tempo to {}", .{tempo});
    }

    /// Stop playing any current music track.
    pub fn stopMusic(_: *Self) void {
        log.debug("stopMusic: stop playing", .{});
    }

    /// Play a sound effect from the specified resource on the specified channel.
    pub fn playSound(_: *Self, sound_data: []const u8, channel_id: audio.ChannelID, volume: audio.Volume, frequency_id: audio.FrequencyID) !void {
        const sound = try audio.SoundResource.parse(sound_data);

        log.debug("playSound: play {*} on channel {} at volume {}, frequency {} (has intro: {}, loops: {})", .{
            sound_data,
            channel_id,
            volume,
            frequency_id.frequency(),
            sound.intro != null,
            sound.loop != null,
        });
    }

    /// Stop any sound effect playing on the specified channel.
    pub fn stopChannel(_: *Self, channel_id: audio.ChannelID) void {
        log.debug("stopChannel: stop playing on channel {}", .{channel_id});
    }
};

// -- Tests --

const testing = @import("utils").testing;

test "Everything compiles" {
    testing.refAllDecls(Audio);
}
