//! Music resources have the following big-endian data layout:
//! (Byte offset, type, purpose, description)
//! -- HEADER --
//! 0..2     u16            tempo            The tempo at which to play the rows of the music track.
//!                                          TODO: figure out unit and range.
//! 2..62    [15][2]u16     instruments      15 entries of 2 words each. See Instrument for layout.
//! 62-64    u16            sequence length  Number of used entries in sequence block.
//!                                          Legal range is 0-128, so top byte goes unused.
//! 64..192  [128]u8        sequence         List of pattern indexes to play in order
//! -- DATA --
//! 192..end [64][4][2]u16  patterns         Each pattern is 64 rows of 4 channel events:
//!                                          1 event for each channel, 2 words each.
//!                                          See ChannelEvent for layout.
//!
//! This appears to be adapted from the ProTracker MOD format, which also used 64 rows per pattern
//! and supported a sequence of 128 patterns: https://www.exotica.org.uk/wiki/Protracker
//! Another World replaced the MOD format's list of 32 samples embedded after the end of pattern data
//! with a list of 16 instruments that referred to sound resources stored separately in the game files.

const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const resources = anotherworld.resources;
const audio = anotherworld.audio;
const vm = anotherworld.vm;
const static_limits = anotherworld.static_limits;

/// Parses an Another World music resource into a structure that can be played back on a mixer.
pub const MusicResource = struct {
    /// The default tempo to play this track, if no custom tempo was specified.
    tempo: audio.Tempo,
    /// The resources and default volumes of each instrument used in the track,
    /// indexed by instrument ID. A null means no instrument will be played in that slot.
    instruments: [static_limits.max_instruments]?Instrument,
    /// The sequence of patterns in the order they should be played.
    /// Will be at most 128 entries long: see static_limits.max_pattern_sequence_length.
    sequence: []const PatternID,
    /// The raw byte data of the patterns themselves.
    /// Interpreted into patterns by `iteratePattern`; should not be accessed directly.
    _raw_pattern_data: []const u8,

    const Self = @This();

    /// Parse a slice of resource data as a music track.
    /// Returns a music resource, or an error if the data was malformed.
    /// The resource stores pointers into the slice, and is only valid for the lifetime of the slice.
    pub fn parse(data: []const u8) ParseError!Self {
        if (data.len < DataLayout.patterns) {
            return error.TruncatedData;
        }

        const tempo_data = data[DataLayout.tempo..DataLayout.instruments];
        const raw_instrument_data = data[DataLayout.instruments..DataLayout.sequence_length];
        const sequence_length_data = data[DataLayout.sequence_length..DataLayout.sequence];
        const sequence_data = data[DataLayout.sequence..DataLayout.patterns];
        const raw_pattern_data = data[DataLayout.patterns..];

        const tempo = std.mem.readIntBig(u16, tempo_data);
        if (tempo == 0) {
            return error.InvalidTempo;
        }

        const sequence_length = std.mem.readIntBig(u16, sequence_length_data);
        if (sequence_length == 0) {
            return error.SequenceEmpty;
        }
        if (sequence_length > static_limits.max_pattern_sequence_length) {
            return error.SequenceTooLong;
        }
        const sequence = sequence_data[0..sequence_length];

        // The pattern section must contain at least as many patterns as are listed in the sequence.
        // (We allow additional padding after the end of the expected pattern data.)
        const max_pattern_id: usize = std.mem.max(PatternID, sequence);
        const required_pattern_data_len = (max_pattern_id + 1) * @sizeOf(RawPattern);
        if (raw_pattern_data.len < required_pattern_data_len) {
            if (@rem(raw_pattern_data.len, @sizeOf(RawPattern)) != 0) {
                // If the pattern section doesn't fall on an even pattern boundary,
                // it likely means the data was truncated.
                return error.TruncatedData;
            } else {
                // If the pattern section does fall on an even pattern boundary,
                // it likely means the sequence refers to a pattern ID that isn't present.
                return error.InvalidPatternID;
            }
        }

        var self = Self{
            .tempo = tempo,
            .instruments = undefined,
            .sequence = sequence,
            ._raw_pattern_data = raw_pattern_data,
        };

        const segmented_instrument_data = @ptrCast(*const [static_limits.max_instruments]Instrument.Raw, raw_instrument_data);

        for (self.instruments) |*instrument, index| {
            instrument.* = Instrument.parse(segmented_instrument_data[index]);
        }

        return self;
    }

    /// Returns an iterator of the sequence of pattern IDs in this music track,
    /// indicating the order in which patterns should be played. The sequence may repeat patterns.
    /// This takes a starting offset into the sequence: use 0 to start at the beginning.
    /// Returns error.InvalidOffset if the specified offset is beyond the end of the sequence.
    ///
    /// Usage:
    ///
    /// var sequence_iterator = try music_resource.iterateSequence(0);
    /// while (try sequence_iterator.next()) |pattern_id| {
    ///     playPattern(pattern_id);
    /// }
    pub fn iterateSequence(self: Self, starting_offset: audio.Offset) IterateSequenceError!SequenceIterator {
        if (starting_offset >= self.sequence.len) return error.InvalidOffset;
        return SequenceIterator{ .counter = starting_offset, .sequence = self.sequence };
    }

    /// Returns an iterator that loops through the 64 rows of a specific pattern.
    /// On each row, it returns a block of 4 events to process on each channel.
    /// Returns error.InvalidPatternID if the specified pattern ID was outside
    /// the range of the resource.
    ///
    /// Usage:
    ///
    /// var iterator = try music_resource.iteratePattern(pattern_id);
    /// while (try iterator.next()) |events| {
    ///     playEventsOnMixerChannels(events);
    /// }
    pub fn iteratePattern(self: Self, index: PatternID) IteratePatternError!PatternIterator {
        const start = @as(usize, index) * @sizeOf(RawPattern);
        const end = start + @sizeOf(RawPattern);
        if (end > self._raw_pattern_data.len) {
            return error.InvalidPatternID;
        }

        const raw_pattern = @ptrCast(*const RawPattern, self._raw_pattern_data[start..end]);
        return PatternIterator{ .pattern = raw_pattern };
    }

    pub const Instrument = @import("instrument.zig").Instrument;
    pub const ChannelEvent = @import("channel_event.zig").ChannelEvent;

    /// The ID of a pattern.
    pub const PatternID = u8;

    /// Errors that can be produced by iterateSequence().
    pub const IterateSequenceError = error{
        /// The specified starting offset was beyond the end of the sequence.
        InvalidOffset,
    };

    /// Errors that can be produced by iteratePattern().
    pub const IteratePatternError = error{
        /// The specified pattern ID was not present in the music track.
        InvalidPatternID,
    };

    /// Errors that can be produced by parse().
    pub const ParseError = error{
        /// The slice was too short to accommodate all expected music data.
        TruncatedData,
        /// The music track defined an empty pattern sequence.
        SequenceEmpty,
        /// The music track defined a pattern sequence longer than 128 entries.
        SequenceTooLong,
        /// The music track defined an invalid tempo.
        InvalidTempo,
        /// The sequence referred to a pattern ID that was not present in the music data.
        InvalidPatternID,
    };

    /// An iterator that iterates through each pattern ID defined in the sequence.
    /// Returned by MusicResource.iterateSequence().
    pub const SequenceIterator = struct {
        sequence: []const PatternID,
        counter: usize = 0,

        /// Returns the next pattern ID in the sequence.
        /// Returns null once it reaches the end of the sequence.
        pub fn next(self: *SequenceIterator) ?PatternID {
            if (self.isAtEnd()) return null;

            const pattern_id = self.sequence[self.counter];
            self.counter += 1;
            return pattern_id;
        }

        /// Returns whether the iterator has reached the end of the sequence.
        pub fn isAtEnd(self: SequenceIterator) bool {
            return self.counter >= self.sequence.len;
        }
    };

    /// An iterator that iterates through each row of 4 channel events in a pattern.
    /// Returned by MusicResource.iteratePattern().
    pub const PatternIterator = struct {
        pattern: *const RawPattern,
        counter: usize = 0,

        /// Returns the next batch of 4 channel events from the pattern.
        /// Returns null once it reaches the end of the pattern.
        /// Returns an error if the iterator reaches a channel event that can't be parsed.
        pub fn next(self: *PatternIterator) ChannelEvent.ParseError!?ChannelEvents {
            if (self.isAtEnd()) return null;

            const raw_events = &self.pattern[self.counter];
            var events: ChannelEvents = undefined;
            for (events) |*event, index| {
                event.* = try ChannelEvent.parse(raw_events[index]);
            }

            self.counter += 1;

            return events;
        }

        /// Returns whether the iterator has reached the end of the pattern.
        pub fn isAtEnd(self: PatternIterator) bool {
            return self.counter >= self.pattern.len;
        }

        pub const ChannelEvents = [static_limits.channel_count]ChannelEvent;
    };

    const RawPattern = [static_limits.rows_per_pattern]RawChannelEvents;
    const RawChannelEvents = [static_limits.channel_count]ChannelEvent.Raw;
};

/// Data offsets within a music resource.
const DataLayout = struct {
    // The starting offset of the tempo
    const tempo = 0x00;
    // The starting offset of the instruments block
    const instruments = 0x02;
    // The starting offset of the sequence length
    const sequence_length = 0x3E;
    // The starting offset of the sequence list
    const sequence = 0x40;
    // The starting offset of pattern data
    const patterns = 0xC0;

    comptime {
        std.debug.assert((sequence_length - instruments) / @sizeOf(MusicResource.Instrument.Raw) == static_limits.max_instruments);
        std.debug.assert((patterns - sequence) / @sizeOf(MusicResource.PatternID) == static_limits.max_pattern_sequence_length);
    }
};

const Fixtures = struct {
    const valid_instruments = @bitCast([60]u8, MusicResource.Instrument.Fixtures.instrument ** static_limits.max_instruments);

    const valid_sequence = [_]u8{ 0, 1, 2, 3, 4, 5 };
    const padded_valid_sequence = valid_sequence ++ ([_]u8{0} ** (static_limits.max_pattern_sequence_length - valid_sequence.len));

    // zig fmt: off
    const valid_header = [_]u8{}
        ++ [_]u8{ 0xCA, 0xFE } // Tempo: 0xCAFE = 51966
        ++ valid_instruments
        ++ [_]u8{ 0x00, 0x06 } // Sequence length: 0x0003 = 6
        ++ padded_valid_sequence
    ;

    const header_with_invalid_tempo = [_]u8{}
        ++ [_]u8{0x00, 0x00 } // Tempo: 0x0000 = 0, too low
        ++ valid_instruments
        ++ [_]u8{ 0x00, 0x06 } // Sequence length: 0x0003 = 6
        ++ padded_valid_sequence
    ;

    const header_with_empty_sequence = [_]u8{}
        ++ [_]u8{ 0xCA, 0xFE } // Tempo: 0xCAFE = 51966
        ++ valid_instruments
        ++ [_]u8{ 0x00, 0x00 } // Sequence length: 0x0000 = 0, too short
        ++ padded_valid_sequence
    ;

    const header_with_sequence_too_long = [_]u8{}
        ++ [_]u8{ 0xCA, 0xFE } // Tempo: 0xCAFE = 51966
        ++ valid_instruments
        ++ [_]u8{ 0x00, 0x81 } // Sequence length: 129, too long
        ++ padded_valid_sequence
    ;
    // zig fmt: on

    const valid_pattern_row = MusicResource.RawChannelEvents{
        MusicResource.ChannelEvent.Fixtures.play,
        MusicResource.ChannelEvent.Fixtures.set_mark,
        MusicResource.ChannelEvent.Fixtures.stop,
        MusicResource.ChannelEvent.Fixtures.noop,
    };

    const valid_pattern = @bitCast([1024]u8, valid_pattern_row ** static_limits.rows_per_pattern);

    const invalid_pattern_row = MusicResource.RawChannelEvents{
        MusicResource.ChannelEvent.Fixtures.play_invalid_instrument_id,
        MusicResource.ChannelEvent.Fixtures.play_invalid_effect,
        MusicResource.ChannelEvent.Fixtures.stop_with_junk,
        MusicResource.ChannelEvent.Fixtures.noop_with_junk,
    };
    const invalid_pattern = @bitCast([1024]u8, invalid_pattern_row ** static_limits.rows_per_pattern);

    // The sequence contains IDs up to 5, therefore we must have at least 6 patterns
    const valid_music = valid_header ++ (valid_pattern ** 6);

    const music_with_invalid_tempo = header_with_invalid_tempo ++ (valid_pattern ** 6);
    const music_with_empty_sequence = header_with_empty_sequence;
    const music_with_sequence_too_long = header_with_sequence_too_long ++ (valid_pattern ** 6);

    const music_with_too_few_patterns = valid_header ++ (valid_pattern ** 5);
    const music_with_invalid_patterns = valid_header ++ (invalid_pattern ** 6);

    comptime {
        std.debug.assert(valid_header.len == 192);
    }
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(MusicResource);
}

// -- parse tests --
test "parse returns expected music resource for valid music data" {
    const music = try MusicResource.parse(&Fixtures.valid_music);

    const expected_sequence = [_]MusicResource.PatternID{ 0, 1, 2, 3, 4, 5 };
    const expected_instruments = [_]?MusicResource.Instrument{MusicResource.Instrument{
        .resource_id = resources.ResourceID.cast(0x1234),
        .volume = audio.Volume.cast(63),
    }} ** static_limits.max_instruments;

    try testing.expectEqual(51966, music.tempo);
    try testing.expectEqualSlices(?MusicResource.Instrument, &expected_instruments, &music.instruments);
    try testing.expectEqualSlices(MusicResource.PatternID, &expected_sequence, music.sequence);

    try testing.expectEqual(6 * @sizeOf(MusicResource.RawPattern), music._raw_pattern_data.len);
}

test "parse returns error.SequenceEmpty for data that defines a 0-length sequence" {
    try testing.expectError(error.SequenceEmpty, MusicResource.parse(&Fixtures.music_with_empty_sequence));
}

test "parse returns error.SequenceEmpty for data that defines a sequence too long" {
    try testing.expectError(error.SequenceTooLong, MusicResource.parse(&Fixtures.music_with_sequence_too_long));
}

test "parse returns error.TruncatedData for data too short for header" {
    const truncated_header = Fixtures.valid_music[0..191];
    try testing.expectError(error.TruncatedData, MusicResource.parse(truncated_header));
}

test "parse returns error.TruncatedData when pattern section is truncated" {
    const truncated_patterns = Fixtures.valid_music[0..(Fixtures.valid_music.len - 1)];
    try testing.expectError(error.TruncatedData, MusicResource.parse(truncated_patterns));
}

test "parse returns error.InvalidPatternID when data does not contain all patterns mentioned in sequence" {
    try testing.expectError(error.InvalidPatternID, MusicResource.parse(&Fixtures.music_with_too_few_patterns));
}

test "parse returns error.InvalidTempo for tempo out of range" {
    try testing.expectError(error.InvalidTempo, MusicResource.parse(&Fixtures.music_with_invalid_tempo));
}

// -- iterateSequence tests --
test "iterateSequence iterates expected sequence from start" {
    const music = try MusicResource.parse(&Fixtures.valid_music);
    var iterator = try music.iterateSequence(0);
    try testing.expectEqual(0, iterator.next());
    try testing.expectEqual(1, iterator.next());
    try testing.expectEqual(2, iterator.next());
    try testing.expectEqual(3, iterator.next());
    try testing.expectEqual(4, iterator.next());
    try testing.expectEqual(5, iterator.next());
    try testing.expectEqual(null, iterator.next());
}

test "iterateSequence iterates partial sequence from non-zero starting offset" {
    const music = try MusicResource.parse(&Fixtures.valid_music);
    var iterator = try music.iterateSequence(4);
    try testing.expectEqual(4, iterator.next());
    try testing.expectEqual(5, iterator.next());
    try testing.expectEqual(null, iterator.next());
}

test "iterateSequence returns error.InvalidOffset when starting offset is out of range" {
    const music = try MusicResource.parse(&Fixtures.valid_music);
    try testing.expectError(error.InvalidOffset, music.iterateSequence(6));
}

// -- iteratePattern tests --
test "iteratePattern iterates pattern with expected events" {
    const music = try MusicResource.parse(&Fixtures.valid_music);
    var iterator = try music.iteratePattern(0);

    const expected_events = MusicResource.PatternIterator.ChannelEvents{
        .{ .play = .{ .instrument_id = 14, .period = 4095, .volume_delta = 63 } },
        .{ .set_mark = 0xCAFE },
        .stop,
        .noop,
    };

    var rows_iterated: usize = 0;
    while (try iterator.next()) |events| : (rows_iterated += 1) {
        try testing.expectEqualSlices(MusicResource.ChannelEvent, &expected_events, &events);
    }
    try testing.expectEqual(static_limits.rows_per_pattern, rows_iterated);
}

test "PatternIterator.next returns error when pattern data contains malformed event" {
    const music = try MusicResource.parse(&Fixtures.music_with_invalid_patterns);
    var iterator = try music.iteratePattern(0);

    try testing.expectError(error.InvalidInstrumentID, iterator.next());
}

test "iteratePattern returns iterator for highest pattern listed in sequence" {
    const music = try MusicResource.parse(&Fixtures.valid_music);
    _ = try music.iteratePattern(5);
}

test "iteratePattern returns iterator for pattern beyond highest pattern listed in sequence" {
    const extended_music = Fixtures.valid_music ++ Fixtures.valid_pattern;
    const music = try MusicResource.parse(&extended_music);
    _ = try music.iteratePattern(6);
}

test "iteratePattern returns error.InvalidPatternID when pattern ID is out of range" {
    const music = try MusicResource.parse(&Fixtures.valid_music);
    try testing.expectError(error.InvalidPatternID, music.iteratePattern(6));
}
