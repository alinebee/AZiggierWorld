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

    /// A list of all instrument resources used by the music track.
    instruments: [static_limits.max_instruments]?LoadedInstrument,

    /// An iterator for the sequence of patterns in the music track.
    sequence_iterator: MusicResource.SequenceIterator,

    /// An iterator for the current pattern.
    pattern_iterator: ?MusicResource.PatternIterator,

    const Self = @This();

    fn init(music: audio.MusicResource, repository: anytype) LoadError!Self {
        var self = Self{
            .music = music,
            .instruments = undefined,
            .sequence_iterator = undefined,
            .pattern_iterator = null,
        };

        for (self.instruments) |*loaded_instrument, index| {
            loaded_instrument.* = if (music.instruments[index]) |instrument| {
                try LoadedInstrument.init(instrument, repository);
            } else {
                null;
            };
        }
        self.sequence_iterator = music.iterateSequence();

        return self;
    }

    /// Returns whether there are more beats left in the music track.
    /// Returns an error if there was a problem reading pattern data.
    pub fn playNextBeat(self: *Self) PlayError!bool {
        // Attempt to load the next pattern if we don't have one lined up
        if (self.pattern_iterator == null) {
            if (self.sequence_iterator.next()) |pattern_id| {
                self.pattern_iterator = try self.music.iteratePattern(pattern_id);
            } else {
                // We've reached the end of the music track
                return false;
            }
        }

        if (try pattern_iterator.?.next()) |events| {
            for (events) |event, index| {
                try self.processEvent(event, ChannelID.cast(index));
            }
            return !self.pattern_iterator.isAtEnd();
        } else {
            self.pattern_iterator = null;
            return !self.sequence_iterator.isAtEnd();
        }
    }

    /// Handle a music event on the specified channel.
    fn processEvent(self: Self, event: audio.MusicResource.ChannelEvent, channel_id: vm.ChannelID) void {
        switch (event) {
            .play => |play| {
                const instrument = self.instruments[play.instrument_id];
                const adjusted_volume = @as(i16, instrument.volume) + play.volume_delta;
                log.debug("Play channel #{}: Instrument #{}, frequency: {}, volume: {}", .{
                    channel_id,
                    play.instrument_id,
                    play.frequency,
                    adjusted_volume,
                });
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
    };
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(MusicPlayer);
}
