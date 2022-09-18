const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const static_limits = anotherworld.static_limits;
const timing = anotherworld.timing;
const log = anotherworld.log;

/// Plays back an Another World music resource, advancing it from pattern to pattern and row to row
/// in response to elapsed time and playing its channel events on a mixer.
pub const MusicPlayer = struct {
    /// The music track being played.
    music: audio.MusicResource,

    /// A list of all instrument resources used by the music track.
    instruments: [static_limits.max_instruments]?LoadedInstrument,

    /// An iterator for the sequence of patterns in the music track.
    sequence_iterator: audio.MusicResource.SequenceIterator,

    /// An iterator for the current pattern.
    pattern_iterator: audio.MusicResource.PatternIterator,

    /// The tempo at which to play the track: how many milliseconds to wait between each row of each pattern.
    ms_per_row: timing.Milliseconds,

    /// The number of milliseconds left over after the last row was played.
    /// Will be between 0 and ms_per_row.
    ms_remaining: timing.Milliseconds = 0,

    /// The timing mode to use to compute tempo and frequency.
    timing_mode: timing.TimingMode,

    const Self = @This();

    /// Create a player that plays from the beginning to the end of the specified music track,
    /// loading instrument data from the specified repository.
    pub fn init(music: audio.MusicResource, repository: anytype, timing_mode: timing.TimingMode, offset: audio.Offset, custom_tempo: ?audio.Tempo) LoadError!Self {
        const ms_per_row = timing_mode.msFromTempo(custom_tempo orelse music.tempo);
        if (ms_per_row == 0) {
            return error.InvalidTempo;
        }

        var self = Self{
            .music = music,
            .ms_per_row = ms_per_row,
            .timing_mode = timing_mode,
            .instruments = undefined,
            .sequence_iterator = undefined,
            .pattern_iterator = undefined,
        };

        for (self.instruments) |*loaded_instrument, index| {
            if (music.instruments[index]) |instrument| {
                loaded_instrument.* = try LoadedInstrument.init(instrument, repository);
            } else {
                loaded_instrument.* = null;
            }
        }

        self.sequence_iterator = try music.iterateSequence(offset);
        if (self.sequence_iterator.next()) |first_pattern_id| {
            self.pattern_iterator = try music.iteratePattern(first_pattern_id);
        } else {
            return error.InvalidOffset;
        }

        return self;
    }

    /// Modifies the tempo at which the music track is played back.
    /// Returns error.InvalidTempo if the tempo was out of range.
    pub fn setTempo(self: *Self, tempo: audio.Tempo) SetTempoError!void {
        const ms_per_row = self.timing_mode.msFromTempo(tempo);
        if (ms_per_row == 0) {
            return error.InvalidTempo;
        }
        self.ms_per_row = ms_per_row;
    }

    /// Process the next n milliseconds of the music track, where n is the elapsed time
    /// since the previous call to playForDuration.
    /// Returns a PlayError if the end of the track was reached or music data could not be read.
    pub fn playForDuration(self: *Self, mixer: *audio.Mixer, time: timing.Milliseconds) PlayError!void {
        std.debug.assert(self.ms_per_row > 0);

        self.ms_remaining += time;
        while (self.ms_remaining >= self.ms_per_row) : (self.ms_remaining -= self.ms_per_row) {
            try self.playNextRow(mixer);
        }
    }

    /// Whether the music track has finished playing through.
    pub fn isAtEnd(self: Self) bool {
        return self.sequence_iterator.isAtEnd() and self.pattern_iterator.isAtEnd();
    }

    // -- Private methods --

    /// Process the next row of events for each channel in the music track.
    /// Returns a PlayError if the end of the track was reached or music data could not be read.
    fn playNextRow(self: *Self, mixer: *audio.Mixer) PlayError!void {
        while (true) {
            if (try self.pattern_iterator.next()) |events| {
                for (events) |event, index| {
                    try self.processEvent(event, mixer, audio.ChannelID.cast(index));
                }
            } else if (self.sequence_iterator.next()) |pattern_id| {
                // If we've finished the current pattern, load the next pattern and try again
                self.pattern_iterator = try self.music.iteratePattern(pattern_id);
            } else {
                return error.EndOfTrack;
            }
        }
    }

    /// Handle a music event on the specified channel of the mixer.
    fn processEvent(self: Self, event: audio.MusicResource.ChannelEvent, mixer: *audio.Mixer, channel_id: audio.ChannelID) PlayError!void {
        switch (event) {
            .play => |play| {
                if (self.instruments[play.instrument_id]) |instrument| {
                    const frequency_in_hz = self.timing_mode.hzFromPeriod(play.period);
                    const adjusted_volume = instrument.volume.rampedBy(play.volume_delta);

                    mixer.play(instrument.resource, channel_id, frequency_in_hz, adjusted_volume);
                } else {
                    return error.MissingInstrument;
                }
            },
            .set_mark => |mark_value| {
                log.debug("Set mark: #{}", .{mark_value});
            },
            .stop => {
                mixer.stop(channel_id);
            },
            .noop => {},
        }
    }

    // -- Public constants --

    /// The possible errors that can occur from init().
    pub const LoadError = audio.MusicResource.IterateSequenceError || audio.MusicResource.IteratePatternError || audio.SoundResource.ParseError || error{
        /// One of the sound resources referenced in the music track was not yet loaded.
        SoundNotLoaded,
        /// An invalid custom tempo was specified.
        InvalidTempo,
        /// A music resource specified an instrument resource ID that was out of range.
        InvalidResourceID,
        /// A music resource specified an instrument resource ID that was not a sound effect.
        UnexpectedResourceType,
    };

    /// The possible errors that can occur from a call to setTempo().
    pub const SetTempoError = error{
        /// An invalid tempo was specified.
        InvalidTempo,
    };

    /// The possible errors that can occur from a call to playForDuration().
    pub const PlayError = audio.MusicResource.IteratePatternError || audio.MusicResource.ChannelEvent.ParseError || error{
        /// Playback reached the end of the track. This is the normal exit condition for the track.
        EndOfTrack,
        /// Attempted to play an instrument ID that didn't have an instrument assigned.
        MissingInstrument,
    };

    // -- Private constants --

    const LoadedInstrument = struct {
        resource: audio.SoundResource,
        volume: audio.Volume,

        fn init(instrument: audio.MusicResource.Instrument, repository: anytype) LoadError!LoadedInstrument {
            if (try repository.resourceLocation(instrument.resource_id, .sound_or_empty)) |sound_data| {
                return LoadedInstrument{
                    .resource = try audio.SoundResource.parse(sound_data),
                    .volume = instrument.volume,
                };
            } else {
                return error.SoundNotLoaded;
            }
        }
    };
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(MusicPlayer);
}
