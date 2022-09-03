const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const vm = anotherworld.vm;
const static_limits = anotherworld.static_limits;
const timing = anotherworld.timing;
const log = anotherworld.log;

/// Use PAL timing for the tempo of music tracks and frequency of samples.
/// This is presumably what they were composed in and originally intended for.
/// TODO: the reference code seems to use NTSC values for frequency calculations
/// (see: https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/sfxplayer.cpp#L196)
/// but seems to fudge the tempo calculations using a constant that's close to PAL
/// (see: https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/sfxplayer.cpp#L42)
/// Determine what the original DOS implementation used.
const timing_mode = timing.TimingMode.default;

pub const MusicPlayer = struct {
    const LoadedInstrument = struct {
        resource: audio.SoundResource,
        volume: audio.Volume,

        fn init(instrument: audio.MusicResource.Instrument, repository: anytype) LoadError!LoadedInstrument {
            const sound_data = repository.resourceLocation(instrument.resource_id) orelse return error.SoundNotLoaded;
            return LoadedInstrument{
                .resource = try SoundResource.parse(sound_data),
                .volume = instrument.volume,
            };
        }
    };

    /// The music track being played.
    music: audio.MusicResource,

    /// A list of all instrument resources used by the music track.
    instruments: [static_limits.max_instruments]?LoadedInstrument,

    /// An iterator for the sequence of patterns in the music track.
    sequence_iterator: MusicResource.SequenceIterator,

    /// An iterator for the current pattern.
    pattern_iterator: MusicResource.PatternIterator,

    /// The tempo at which to play the track: how many milliseconds to wait between each row of each pattern.
    ms_per_row: timing.Milliseconds,

    /// The number of milliseconds left over after the last row was played.
    /// Will be between 0 and ms_per_row.
    ms_remaining: timing.Milliseconds,

    const Self = @This();

    /// Create a player that plays from the beginning to the end of the specified music track,
    /// loading instrument data from the specified repository.
    fn init(music: audio.MusicResource, repository: anytype, offset: audio.Offset, custom_tempo: ?audio.Tempo) LoadError!Self {
        const ms_per_row = timing_mode.msFromTempo(custom_tempo orelse music.tempo);
        if (ms_per_row == 0) {
            return error.InvalidTempo;
        }

        var self = Self{
            .music = music,
            .ms_per_row = ms_per_row,
            .instruments = undefined,
            .sequence_iterator = undefined,
            .pattern_iterator = undefined,
        };

        for (self.instruments) |*loaded_instrument, index| {
            loaded_instrument.* = if (music.instruments[index]) |instrument| {
                try LoadedInstrument.init(instrument, repository);
            } else {
                null;
            };
        }

        self.sequence_iterator = try music.iterateSequence(offset);
        if (self.sequence_iterator.next()) |first_pattern_id| {
            self.pattern_iterator = try music.iteratePattern(first_pattern_id);
        } else {
            return error.InvalidOffset;
        }

        return self;
    }

    /// Process the next n milliseconds of the music track, where n is the elapsed time
    /// since the previous call to playForDuration.
    /// Returns a PlayError if the end of the track was reached or music data could not be read.
    pub fn playForDuration(self: *Self, time: timing.Milliseconds) PlayError!void {
        self.ms_remaining += time;
        while (self.ms_remaining >= self.ms_per_row) : (self.ms_remaining -= self.ms_per_row) {
            try self.advanceToNextRow();
        }
    }

    /// Process the next row of events for each channel in the music track.
    /// Returns a PlayError if the end of the track was reached or music data could not be read.
    fn advanceToNextRow(self: *Self) PlayError!void {
        while (true) {
            if (try pattern_iterator.next()) |events| {
                for (events) |event, index| {
                    try self.processEvent(event, ChannelID.cast(index));
                }
            } else if (self.sequence_iterator.next()) |pattern_id| {
                // If we've finished the current pattern, load the next pattern and try again
                self.pattern_iterator = try self.music.iteratePattern(pattern_id);
            } else {
                return error.EndOfTrack;
            }
        }
    }

    /// Handle a music event on the specified channel.
    fn processEvent(self: Self, event: audio.MusicResource.ChannelEvent, channel_id: vm.ChannelID) void {
        switch (event) {
            .play => |play| {
                if (self.instruments[play.instrument_id]) |instrument| {
                    const adjusted_volume = @as(i16, instrument.volume) + play.volume_delta;
                    const frequency_in_hz = timing_mode.hzFromPeriod(play.period);
                    log.debug("Play channel #{}: Instrument #{}, frequency: {}, volume: {}", .{
                        channel_id,
                        play.instrument_id,
                        play.period,
                        adjusted_volume,
                    });
                }
            },
            .set_mark => |mark_value| {
                log.debug("Set mark: #{}", .{mark_value});
            },
            .stop => {
                log.debug("Stop channel #{}", .{channel_id});
            },
            .noop => {},
        }
    }

    fn isAtEnd() bool {
        if (self.sequence.isAtEnd() == false) return false;
        if (self.pattern_iterator) |pattern_iterator| {
            return pattern_iterator.isAtEnd();
        } else {
            return true;
        }
    }

    /// The possible errors that can occur from init().
    pub const LoadError = audio.MusicResource.Instrument.ParseError || audio.MusicResource.IterateSequenceError || error{
        /// One of the sound resources referenced in the music track was not yet loaded.
        SoundNotLoaded,
        /// An invalid custom tempo was specified.
        InvalidTempo,
    };

    /// The possible errors that can occur from playForTime().
    pub const PlayError = audio.MusicResource.IteratePatternError || audio.MusicResource.ChannelEvent.ParseError || error{
        /// Playback reached the end of the track.
        EndOfTrack,
    };
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(MusicPlayer);
}
