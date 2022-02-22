//! This file defines types and functions for converting from Another World's 12-bit RGB
//! palette data into 32-bit colors that can be more easily consumed by the emulator's host.
//!
//! The conversion from 4-bit channels to 8-bit matches the reference implementation here:
//! https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/sysImplementation.cpp#L88-L90
//!
//! That algorithm uses bit-shifting to spread each 4-bit channel value out to 8 bits,
//! and it produces colors where the lower 2 bits of each channel are always 0. This results
//! in a jagged color ramp where the full range of 0...15 maps to 0...252 instead of 0...255.
//!
//! The algorithm was probably adapted directly from the MS-DOS port of the game,
//! which targeted the VGA adapter: VGA used 6 bits per channel rather than 8.
//! https://en.wikipedia.org/wiki/Video_Graphics_Array
//!
//! The reference implementation first spread colors evenly out to 6 bits, then shifted
//! to get to 8. We could get a smooth ramp that covers the full range by simply multiplying
//! the 4-bit values by 17, since 17 * 15 == 255. For now though, this sticks with the original
//! algorithm under the assumption that it better matches the rendering of the original MS-DOS game.
//!
//! (This may be an erroneous assumption: the 6-bit-per-channel values would have covered
//! the full VGA gamut, so it's inaccurate to widen them to an 8-bit-per-channel gamut
//! by leaving the lower 2 bits empty.)

/// A 32-bit color value parsed from Another World's resource data.
pub const Instance = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

/// Color values are stored in resource data as 16-bit big-endian integers.
pub const Raw = u16;

/// Convert a 16-bit raw color value from Another World game data into an RGB color.
pub fn parse(raw: Raw) Instance {
    // Palette entries use 4 bits per channel but were stored
    // as 16 bits with the layout xxxxRRRRGGGGBBBB:
    // First 4 bits are unused and are just for alignment.
    // Next 4 are red, next 4 are green, next 4 are blue.
    const raw_r = @truncate(u4, raw >> 8);
    const raw_g = @truncate(u4, raw >> 4);
    const raw_b = @truncate(u4, raw >> 0);

    return .{
        .r = spread(raw_r),
        .g = spread(raw_g),
        .b = spread(raw_b),
        .a = 255,
    };
}

/// Take a 4-bit channel value and spread it into an 8-bit value.
fn spread(value: u4) u8 {
    const value_6bit: u6 = (@as(u6, value) << 2) | (@as(u6, value) >> 2);
    const value_8bit: u8 = @as(u8, value_6bit) << 2;
    return value_8bit;
}

// -- Examples --

const Fixtures = struct {
    // zig fmt: off
    const red:      Raw = 0b0000_1111_0000_0000;
    const green:    Raw = 0b0000_0000_1111_0000;
    const blue:     Raw = 0b0000_0000_0000_1111;
    const white:    Raw = 0b0000_1111_1111_1111;
    const grey:     Raw = 0b0000_1000_1000_1000;
    const black:    Raw = 0b0000_0000_0000_0000;
    // zig fmt: on
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "spread converts 4-bit values to expected 8-bit values" {
    // zig fmt: off
    //                                              // smooth ramp      drift from smooth
    try testing.expectEqual(0,      spread(0));     // 0  * 17 = 0      0   - 0   = 0
    try testing.expectEqual(16,     spread(1));     // 1  * 17 = 17     17  - 16  = 1
    try testing.expectEqual(32,     spread(2));     // 2  * 17 = 34     34  - 32  = 2
    try testing.expectEqual(48,     spread(3));     // 3  * 17 = 51     51  - 48  = 3
    try testing.expectEqual(68,     spread(4));     // 4  * 17 = 68     68  - 68  = 0
    try testing.expectEqual(84,     spread(5));     // 5  * 17 = 85     85  - 84  = 1
    try testing.expectEqual(100,    spread(6));     // 6  * 17 = 102    102 - 100 = 2
    try testing.expectEqual(116,    spread(7));     // 7  * 17 = 119    119 - 116 = 3
    try testing.expectEqual(136,    spread(8));     // 8  * 17 = 136    136 - 136 = 0
    try testing.expectEqual(152,    spread(9));     // 9  * 17 = 153    153 - 152 = 1
    try testing.expectEqual(168,    spread(10));    // 10 * 17 = 170    170 - 168 = 2
    try testing.expectEqual(184,    spread(11));    // 11 * 17 = 187    187 - 184 = 3
    try testing.expectEqual(204,    spread(12));    // 12 * 17 = 204    204 - 204 = 0
    try testing.expectEqual(220,    spread(13));    // 13 * 17 = 221    221 - 220 = 1
    try testing.expectEqual(236,    spread(14));    // 14 * 17 = 238    238 - 236 = 2
    try testing.expectEqual(252,    spread(15));    // 15 * 17 = 255    255 - 252 = 3
    // zig fmt: on
}

test "parse converts 12-bit colors to expected 24-bit colors" {
    // zig fmt: off
    try testing.expectEqual(.{ .r = 252, .g = 0,   .b = 0, .a = 255 },    parse(Fixtures.red));
    try testing.expectEqual(.{ .r = 0,   .g = 252, .b = 0, .a = 255 },    parse(Fixtures.green));
    try testing.expectEqual(.{ .r = 0,   .g = 0,   .b = 252, .a = 255 },  parse(Fixtures.blue));
    try testing.expectEqual(.{ .r = 252, .g = 252, .b = 252, .a = 255 },  parse(Fixtures.white));
    try testing.expectEqual(.{ .r = 136, .g = 136, .b = 136, .a = 255 },  parse(Fixtures.grey));
    try testing.expectEqual(.{ .r = 0,   .g = 0,   .b = 0, .a = 255 },    parse(Fixtures.black));
    // zig fmt: on
}
