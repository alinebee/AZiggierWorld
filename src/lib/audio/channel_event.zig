const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const vm = anotherworld.vm;
const log = anotherworld.log;

pub const ChannelEvent = union(enum) {
    // Start playing an instrument on the channel.
    play: struct {
        // The index of the instrument to play, from the song's bank of 15 instruments.
        instrument_id: u4,
        // The amount by which to adjust the instrument's base volume up or down.
        volume_delta: i16,
        // The frequency to play the instrument at.
        frequency: audio.Frequency,
    },
    // Set RegisterID.music_mark to the specified value.
    set_mark: vm.Register.Unsigned,
    // Stop the channel.
    stop,
    // Don't do anything to the channel.
    noop,

    const Self = @This();

    pub fn parse(data: Raw) ParseError!Self {
        const control_value_1 = std.mem.readIntBig(u16, data[0..2]);
        const control_value_2 = std.mem.readIntBig(u16, data[2..4]);

        switch (control_value_1) {
            0x0000 => {
                return Self.noop;
            },
            0xFFFD => {
                return Self{ .set_mark = control_value_2 };
            },
            0xFFFE => {
                return Self.stop;
            },
            else => {
                const raw_instrument_id = @truncate(u4, control_value_2 >> 12);
                if (raw_instrument_id == 0) {
                    return error.InvalidInstrumentID;
                }

                const frequency = try amigaPeriodToHz(control_value_1);

                const effect = @truncate(u4, control_value_2 >> 8);
                const raw_volume_delta = @truncate(u8, control_value_2);
                const volume_delta = switch (effect) {
                    5 => @as(i16, raw_volume_delta),
                    6 => -@as(i16, raw_volume_delta),
                    else => 0,
                };

                return Self{ .play = .{
                    .instrument_id = raw_instrument_id - 1,
                    .frequency = frequency,
                    .volume_delta = volume_delta,
                } };
            },
        }
    }

    // Copypasta from reference implementation:
    // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/srcsfxplayer.cpp#L194
    // "convert amiga period value to hz"
    // TODO: document what these magic numbers mean. 7,159,092 is too large to fit into a 16-bit int,
    // which means this code wasn't in the original DOS executable. Perhaps adapted from an Amiga reference?
    fn amigaPeriodToHz(raw_frequency: u16) ParseError!audio.Frequency {
        if (raw_frequency < 55 or raw_frequency >= 4096) {
            return error.InvalidFrequency;
        }
        return @truncate(audio.Frequency, 7_159_092 / @as(usize, raw_frequency) * 2);
    }

    pub const Raw = [4]u8;

    pub const ParseError = error{
        // A play event referred to an instrument that does not exist.
        InvalidInstrumentID,
        // A play event defined a frequency that was out of range.
        InvalidFrequency,
    };
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(ChannelEvent);
}
