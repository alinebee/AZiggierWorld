const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const vm = anotherworld.vm;
const static_limits = anotherworld.static_limits;
const log = anotherworld.log;

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

    /// The tempo at which to play the track.
    tempo: audio.Tempo,

    /// A list of all instrument resources used by the music track.
    instruments: [static_limits.max_instruments]?LoadedInstrument,

    /// An iterator for the sequence of patterns in the music track.
    sequence_iterator: MusicResource.SequenceIterator,

    /// An iterator for the current pattern.
    pattern_iterator: MusicResource.PatternIterator,

    const Self = @This();

    /// Create a player that plays from the beginning to the end of the specified music track,
    /// loading instrument data from the specified repository.
    fn init(music: audio.MusicResource, repository: anytype, custom_tempo: ?audio.Tempo) LoadError!Self {
        var self = Self{
            .music = music,
            .tempo = custom_tempo orelse music.tempo,
            .instruments = undefined,
            .sequence_iterator = undefined,
            .pattern_iterator = undefined,
        };

        if (self.tempo == 0) {
            return error.InvalidTempo;
        }

        for (self.instruments) |*loaded_instrument, index| {
            loaded_instrument.* = if (music.instruments[index]) |instrument| {
                try LoadedInstrument.init(instrument, repository);
            } else {
                null;
            };
        }

        self.sequence_iterator = music.iterateSequence();
        if (self.sequence_iterator.next()) |first_pattern_id| {
            self.pattern_iterator = try music.iteratePattern(first_pattern_id);
        } else {
            return error.EmptySequence;
        }

        return self;
    }

    /// Process the next "beat" (row of events for each channel) in the music track.
    /// Returns true if there are more beats left in the track,
    /// or false if playback reached the end of the track.
    /// Returns an error if there was a problem reading pattern data.
    pub fn playNextBeat(self: *Self) PlayError!bool {
        while (true) {
            if (try pattern_iterator.next()) |events| {
                for (events) |event, index| {
                    try self.processEvent(event, ChannelID.cast(index));
                }
                return !self.isAtEnd();
            } else if (self.sequence_iterator.next()) |pattern_id| {
                // If we've finished the current pattern, load the next pattern and try again
                self.pattern_iterator = try self.music.iteratePattern(pattern_id);
                continue;
            } else {
                // We've reached the end of the music track
                return false;
            }
        }
    }

    /// Handle a music event on the specified channel.
    fn processEvent(self: Self, event: audio.MusicResource.ChannelEvent, channel_id: vm.ChannelID) void {
        switch (event) {
            .play => |play| {
                if (self.instruments[play.instrument_id]) |instrument| {
                    const adjusted_volume = @as(i16, instrument.volume) + play.volume_delta;
                    log.debug("Play channel #{}: Instrument #{}, frequency: {}, volume: {}", .{
                        channel_id,
                        play.instrument_id,
                        play.frequency,
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

    /// The possible errors that can occur from playNextBeat().
    pub const PlayError = audio.MusicResource.IteratePatternError || audio.MusicResource.ChannelEvent.ParseError;

    /// The possible errors that can occur from init().
    pub const LoadError = audio.MusicResource.Instrument.ParseError || error{
        /// One of the sound resources referenced in the music track was not yet loaded.
        SoundNotLoaded,
        /// The music track has an empty sequence.
        EmptySequence,
        /// An invalid custom tempo was specified.
        InvalidTempo,
    };
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(MusicPlayer);
}
