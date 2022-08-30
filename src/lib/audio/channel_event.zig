//! Channel events in Another World music patterns consist of two 16-bit unsigned word
//! whose meaning depends on the value of the first word.
//! Word 1                  Word 2                  Meaning
//! 0b0000_0000_0000_0000   0b0000_0000_0000_0000   No-op: do nothing on the channel.
//! 0x1111_1111_1111_1110   0b0000_0000_0000_0000   Stop the current channel.
//! 0x1111_1111_1111_1101   0brrrr_rrrr_rrrr_rrrr   Set music mark register to value of second word.
//! 0xffff_ffff_ffff_ffff   0biiii_eeee_vvvv_vvvv   Play sound effect on channel:
//!                                                 - f: Treat all bits of first word as note frequency
//!                                                      (technically Amiga clock period: see amigaPeriodToHz below)
//!                                                 - i: Treat top 4 bits of second word as instrument ID - 1
//!                                                 - e: Treat next 4 bits of second word as "effect bits":
//!                                                      - 5: treat last 8 bits of second word as volume increase
//!                                                      - 6: treat last 8 bits of second word as volume decrease
//!                                                 - v: Value of volume increase/decrease, depending on effect bits.
//!                                                      Ignored unless effect is 5 or 6.
//!
const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const vm = anotherworld.vm;
const log = anotherworld.log;

pub const ChannelEvent = union(enum) {
    /// Start playing an instrument on the channel.
    play: struct {
        /// The index of the instrument to play, from the song's bank of 15 instruments.
        instrument_id: u4,
        /// The amount by which to adjust the instrument's base volume up or down.
        volume_delta: i16,
        /// The frequency to play the instrument at.
        frequency: audio.Frequency,
    },
    /// Set RegisterID.music_mark to the specified value.
    set_mark: vm.Register.Unsigned,
    /// Stop the channel.
    stop,
    /// Don't do anything to the channel.
    noop,

    const Self = @This();

    /// Parses a raw 4-byte code from a stream of pattern data into a channel event.
    /// Returns an error if the code was malformed.
    pub fn parse(data: Raw) ParseError!Self {
        const control_value_1 = std.mem.readIntBig(u16, data[0..2]);
        const control_value_2 = std.mem.readIntBig(u16, data[2..4]);

        switch (control_value_1) {
            0x0000 => {
                if (control_value_2 != 0) return error.MalformedNoopEvent;
                return Self.noop;
            },
            0xFFFD => {
                return Self{ .set_mark = control_value_2 };
            },
            0xFFFE => {
                if (control_value_2 != 0) return error.MalformedStopEvent;
                return Self.stop;
            },
            else => {
                // TODO 0.10: replace shift-and-truncate with packed struct:
                // https://github.com/ziglang/zig/pull/12379
                const raw_instrument_id = @truncate(u4, control_value_2 >> 12);

                // Ignoring index 0, and subtracting 1 from the 4-bit instrument ID,
                // matches the reference implementation but seems like a mistake:
                // it makes the instrument range 0-14 rather than the 0-15 it would be
                // if the implementation had permitted 0 and not substracted 1.
                // (0 isn't needed as a sentinel for "don't play anything" anyway,
                // control_value_1 == 0 already does that.)
                // This means that the music tracks couldn't address instrument 15,
                // even though the instrument array supports 15 instruments.
                //
                // Speculation: the game adopted an existing mod-tracker format
                // but implemented it wrongly.
                if (raw_instrument_id == 0) {
                    return error.InvalidInstrumentID;
                }

                const frequency = try amigaPeriodToHz(control_value_1);

                const effect = @truncate(u4, control_value_2 >> 8);
                const raw_volume_delta = @truncate(u8, control_value_2);
                const volume_delta = switch (effect) {
                    0 => 0,
                    5 => @as(i16, raw_volume_delta),
                    6 => -@as(i16, raw_volume_delta),
                    else => {
                        return error.InvalidEffect;
                    },
                };

                return Self{ .play = .{
                    .instrument_id = raw_instrument_id - 1,
                    .frequency = frequency,
                    .volume_delta = volume_delta,
                } };
            },
        }
    }

    pub const Raw = [4]u8;

    pub const ParseError = error{
        /// A play event referred to an instrument that does not exist.
        InvalidInstrumentID,
        /// A play event defined a frequency that was out of range.
        InvalidFrequency,
        /// A play event defined an unrecognized effect.
        InvalidEffect,
        /// A stop event contained unused junk data.
        MalformedStopEvent,
        /// A no-op event contained unused junk data.
        MalformedNoopEvent,
    };

    // -- Private --

    /// The clock speed of an NTSC Amiga in Hz.
    const ntsc_amiga_clock_hz = 3_579_545;
    /// The clock speed of a PAL Amiga in Hz.
    const pal_amiga_clock_hz = 3_546_895;
    /// The minimum period allowed.
    /// The reference implementation used 55, but the Amiga hardware manual claims that
    /// a period smaller than 124 would be too few tics for the hardware to keep up.
    const min_period = 124;
    /// The maximum period allowed. The Protracker MOD format could not specify a period higher than this,
    /// and all note periods in the Another World game data are well below this.
    const max_period = 4095;

    /// Convert from the "period" of a note in Another World's music format to a frequency in Hz.
    /// NTSC Amigas used a clock speed of 3.579545MhZ to match the NTSC standard; PAL Amigas used 3.546895MhZ.
    /// Another World's music resources specified the frequency (i.e. pitch) of a note as a "period" of the Amiga's
    /// clock value. To get the frequency in Hz to play back the note, we must divide the clock speed by the period.
    ///
    /// References:
    /// -----------
    /// Reference implementation: https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/srcsfxplayer.cpp#L194
    /// Clock speed discussion: https://retrocomputing.stackexchange.com/questions/2146/reason-for-the-amiga-clock-speed
    /// ProTracker MOD format discussion: https://www.exotica.org.uk/wiki/Protracker
    /// Amiga hardware manual: http://amiga.nvg.org/amiga/reference/Hardware_Manual_guide/node00DE.html
    fn amigaPeriodToHz(period: u16) ParseError!audio.Frequency {
        if (period < min_period or period > max_period) {
            return error.InvalidFrequency;
        }
        return @truncate(audio.Frequency, ntsc_amiga_clock_hz / @as(usize, period));
    }
};

const Fixtures = struct {
    // Raw frequency 4095, raw instrument 15, raw effect 5, raw volume 63
    const play = [4]u8{ 0x0F, 0xFF, 0b1111_0101, 0x3F };

    const stop = [4]u8{ 0xFF, 0xFE, 0x00, 0x00 };

    const set_mark = [4]u8{ 0xFF, 0xFD, 0xCA, 0xFE };

    const noop = [4]u8{ 0x00, 0x00, 0x00, 0x00 };

    // Raw period 4095, raw instrument 0, raw effect 5, raw volume 63
    const play_invalid_instrument_id = [4]u8{ 0x0F, 0xFF, 0b0000_0101, 0x3F };

    // Raw period 4096, raw instrument 15, raw effect 5, raw volume 63
    const play_period_too_high = [4]u8{ 0x10, 0x00, 0b1111_0101, 0x3F };

    // Raw period 123, raw instrument 15, raw effect 5, raw volume 63
    const play_period_too_low = [4]u8{ 0x00, 0x7B, 0b1111_0101, 0x3F };

    // Raw period 4095, raw instrument 15, raw effect 4, raw volume 63
    const play_invalid_effect = [4]u8{ 0x0F, 0xFF, 0b1111_0100, 0x3F };

    const stop_with_junk = [4]u8{ 0xFF, 0xFE, 0x12, 0x34 };

    const noop_with_junk = [4]u8{ 0x00, 0x00, 0x12, 0x34 };
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(ChannelEvent);
}

test "parse parses play event" {
    const expected = ChannelEvent{
        .play = .{
            .instrument_id = 14,
            .frequency = 874, // 3,579,545Hz / 4095 period
            .volume_delta = 63,
        },
    };
    try testing.expectEqual(expected, try ChannelEvent.parse(Fixtures.play));
}

test "parse parses set_mark event" {
    const expected = ChannelEvent{ .set_mark = 0xCAFE };
    try testing.expectEqual(expected, try ChannelEvent.parse(Fixtures.set_mark));
}

test "parse parses stop event" {
    try testing.expectEqual(.stop, try ChannelEvent.parse(Fixtures.stop));
}

test "parse parses noop event" {
    try testing.expectEqual(.noop, try ChannelEvent.parse(Fixtures.noop));
}

test "parse returns error.InvalidInstrumentID when play event specifies instrument out of range" {
    try testing.expectError(error.InvalidInstrumentID, ChannelEvent.parse(Fixtures.play_invalid_instrument_id));
}

test "parse returns error.InvalidFrequency when play event specifies frequencies out of range" {
    try testing.expectError(error.InvalidFrequency, ChannelEvent.parse(Fixtures.play_period_too_high));
    try testing.expectError(error.InvalidFrequency, ChannelEvent.parse(Fixtures.play_period_too_low));
}

test "parse returns error.InvalidEffect when play event specifies unknown effect" {
    try testing.expectError(error.InvalidEffect, ChannelEvent.parse(Fixtures.play_invalid_effect));
}

test "parse returns error.MalformedStopEvent when stop event contains junk data" {
    try testing.expectError(error.MalformedStopEvent, ChannelEvent.parse(Fixtures.stop_with_junk));
}

test "parse returns error.MalformedNoopEvent when noop event contains junk data" {
    try testing.expectError(error.MalformedNoopEvent, ChannelEvent.parse(Fixtures.noop_with_junk));
}
