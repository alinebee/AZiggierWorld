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
    sequence: []const PatternID,
    _raw_patterns: []const RawPattern,

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

        // The pattern section must accommodate whole patterns (1024 bytes each)
        if (@rem(raw_pattern_data.len, @sizeOf(RawPattern)) != 0) {
            return error.TruncatedData;
        }

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

        const segmented_instrument_data = @ptrCast(*const [static_limits.max_instruments]Instrument.Raw, raw_instrument_data);

        const segmented_pattern_data = @bitCast([]const RawPattern, raw_pattern_data);
        const highest_pattern_id = std.mem.max(PatternID, sequence);
        if (highest_pattern_id >= segmented_pattern_data.len) {
            return error.TruncatedData;
        }

        var self = Self{
            .tempo = tempo,
            .instruments = undefined,
            .sequence = sequence,
            ._raw_patterns = segmented_pattern_data,
        };

        for (self.instruments) |*instrument, index| {
            instrument.* = Instrument.parse(segmented_instrument_data[index]);
        }

        return self;
    }

    /// Returns an iterator of the sequence of pattern IDs in this music track,
    /// indicating the order in which patterns should be played.
    /// This sequence may repeat patterns.
    pub fn iterateSequence(self: Self) SequenceIterator {
        return .{ .sequence = self.sequence };
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
    ///   playEventsOnMixerChannels(events);
    /// }
    pub fn iteratePattern(self: Self, index: PatternID) IteratePatternError!PatternIterator {
        if (index > self._raw_patterns.len) {
            return error.InvalidPatternID;
        }
        return PatternIterator{ .pattern = &self._raw_patterns[index] };
    }

    pub const Instrument = @import("instrument.zig").Instrument;
    pub const ChannelEvent = @import("channel_event.zig").ChannelEvent;

    /// The ID of a pattern.
    pub const PatternID = u8;

    /// Errors that can be produced by iteratePattern().
    pub const IteratePatternError = error{
        InvalidPatternID,
    };

    /// Errors that can be produced by parse().
    pub const ParseError = error{
        /// The data slice was too short to accommodate all expected pattern data.
        TruncatedData,
        /// The music track defined an empty pattern sequence.
        SequenceEmpty,
        /// The music track defined a pattern sequence longer than 128 entries.
        SequenceTooLong,
        /// The music track defined an invalid tempo.
        InvalidTempo,
    };

    pub const SequenceIterator = struct {
        sequence: []const PatternID,
        counter: usize = 0,

        pub fn next(self: *SequenceIterator) ?PatternID {
            if (self.isAtEnd()) return null;

            const pattern_id = self.sequence[self.counter];
            self.counter += 1;
            return pattern_id;
        }

        pub fn isAtEnd(self: SequenceIterator) bool {
            return self.counter >= self.sequence.len;
        }
    };

    /// An iterator with a next() function that loops through blocks of 4 channel events in a pattern.
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

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(MusicResource);
}
