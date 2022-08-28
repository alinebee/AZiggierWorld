const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const resources = anotherworld.resources;
const audio = anotherworld.audio;
const vm = anotherworld.vm;
const static_limits = anotherworld.static_limits;

const Instrument = @import("instrument.zig").Instrument;
const ChannelEvent = @import("channel_event.zig").ChannelEvent;

const max_sequences = 128;
const max_instruments = 15;
const events_per_pattern = 64;

/// Another World sound effect data has the following big-endian data layout:
/// (Byte offset, type, purpose)
/// ------HEADER------
/// 0..2     u16         delay (TODO: figure out unit and range)
/// 2..62    [u16, u16]  instrument data: resource ID and volume
/// 62-64    u16         number of sequences (legal range from 0-127, high byte unused?)
/// 64..192  [u8]        a list of the indexes of patterns to play in order
/// ------DATA------
/// 192..end u8[]    pattern data (TODO: figure out format)
const DataLayout = struct {
    // The starting offset of the delay
    const delay = 0x00;
    // The starting offset of the instruments block
    const instruments = 0x02;
    // The starting offset of the sequence count
    const sequence_count = 0x3E;
    // The starting offset of the sequences block
    const sequences = 0x40;
    // The starting offset of pattern data
    const pattern_data = 0xC0;

    comptime {
        std.debug.assert((sequence_count - instruments) / @sizeOf(Instrument.Raw) == max_instruments);
        std.debug.assert((pattern_data - sequences) / @sizeOf(MusicResource.PatternID) == max_sequences);
    }
};

const RawChannelEvents = [static_limits.channel_count]ChannelEvent.Raw;
const RawPattern = [events_per_pattern]RawChannelEvents;

pub const MusicResource = struct {
    const SequenceStorage = std.BoundedArray(PatternID, max_sequences);

    pattern_data: []const u8,
    delay: audio.Delay,
    instruments: [max_instruments]?Instrument,
    _raw_sequences: SequenceStorage,

    const Self = @This();

    pub fn parse(data: []const u8) ParseError!Self {
        if (data.len < DataLayout.pattern_data) {
            return error.TruncatedData;
        }

        const delay_data = data[DataLayout.delay..DataLayout.instruments];
        const raw_instrument_data = data[DataLayout.instruments..DataLayout.sequence_count];
        const sequence_count_data = data[DataLayout.sequence_count..DataLayout.sequences];
        const sequence_data = data[DataLayout.sequences..DataLayout.pattern_data];
        const raw_pattern_data = data[DataLayout.pattern_data..];

        const delay = std.mem.readIntBig(u16, delay_data);
        const parsed_sequence_count = std.mem.readIntBig(u16, sequence_count_data);
        const segmented_instrument_data = @ptrCast(*const [max_instruments]Instrument.Raw, raw_instrument_data);

        if (parsed_sequence_count > max_sequences) {
            return error.TooManySequences;
        }

        var self = Self{
            .delay = delay,
            .pattern_data = raw_pattern_data,
            .instruments = undefined,
            ._raw_sequences = SequenceStorage.fromSlice(sequence_data[0..parsed_sequence_count]) catch unreachable,
        };

        for (self.instruments) |*instrument, index| {
            instrument.* = Instrument.parse(segmented_instrument_data[index]);
        }

        return self;
    }

    pub fn sequences(self: Self) []const PatternID {
        return self._raw_sequences.constSlice();
    }

    pub fn iteratePattern(self: Self, index: PatternID) ReadError!PatternIterator {
        const pattern_length: usize = @sizeOf(RawPattern);
        const pattern_start: usize = index * pattern_length;
        const pattern_end: usize = pattern_start + pattern_length;

        if (self.pattern_data.len < pattern_end) {
            return error.InvalidPatternID;
        }

        const data_for_pattern = @ptrCast(*const RawPattern, self.pattern_data[pattern_start..pattern_end]);
        return PatternIterator{ .pattern_data = data_for_pattern };
    }

    pub const PatternID = u8;

    pub const ReadError = error{
        InvalidPatternID,
    };

    pub const ParseError = error{
        TruncatedData,
        TooManySequences,
    };

    pub const PatternIterator = struct {
        pattern_data: *const RawPattern,
        counter: usize = 0,

        /// Returns the next batch of 4 channel events from the reader.
        /// Returns null once it reaches the end of the pattern, or an error if it cannot parse a channel event.
        pub fn next(self: *PatternIterator) ChannelEvent.ParseError!?ChannelEvents {
            if (self.counter >= self.pattern_data.len) {
                return null;
            }

            const raw_events = &self.pattern_data[self.counter];
            var events: ChannelEvents = undefined;
            for (events) |*event, index| {
                event.* = try ChannelEvent.parse(raw_events[index]);
            }

            self.counter += 1;

            return events;
        }

        pub const ChannelEvents = [static_limits.channel_count]ChannelEvent;
    };
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(MusicResource);
}
