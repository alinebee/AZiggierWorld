//! Another World used 16-color palettes where each color is indexed by an integer from 0-15.
//! These color IDs appear in bytecode, polygon resources and video buffers.

const intCast = @import("../utils/introspection.zig").intCast;

/// A color index from 0-15. This is guaranteed to be valid.
pub const Trusted = u4;

/// A raw color index stored in bytecode as an 8-bit unsigned integer.
/// This can potentially be out of range: converted to a Trusted ID with `parse`.
pub const Raw = u8;

pub const Error = error{
    /// Bytecode specified an invalid color ID.
    InvalidColorID,
};

/// Given a raw byte value, return a trusted color ID.
/// Returns error.InvalidColorID if the value is out of range.
pub fn parse(raw_id: Raw) Error!Trusted {
    return intCast(Trusted, raw_id) catch error.InvalidColorID;
}

/// Remap colors 0...7 to colors 8...15. Colors 8...15 will be left as they are.
/// The last 8 colors in a palette are expected to be a lightened/darkened version of the first 8 colors;
/// Ramping them achieves translucency effects like e.g. the headlights of the ferrari in the game intro.
pub fn highlight(color: Trusted) Trusted {
    return color | 0b1000;
}

/// Given a byte containing two 4-bit colors, remaps both colors from 0...7 to 8...15.
/// Colors 8...15 will be left as they are. See `highlight` for more details.
pub fn highlightByte(color_byte: u8) u8 {
    return color_byte | 0b1000_1000;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse succeeds for in-bounds integer" {
    try testing.expectEqual(0, parse(0b0000_0000));
    try testing.expectEqual(15, parse(0b0000_1111));
}

test "parse returns InvalidThreadID for out-of-bounds integer" {
    try testing.expectError(error.InvalidColorID, parse(0b0001_0000));
}

test "highlight remaps lower 8 colors to upper 8 colors" {
    try testing.expectEqual(0b1000, highlight(0b0000));
    try testing.expectEqual(0b1001, highlight(0b0001));
    try testing.expectEqual(0b1010, highlight(0b0010));
    try testing.expectEqual(0b1011, highlight(0b0011));
    try testing.expectEqual(0b1100, highlight(0b0100));
    try testing.expectEqual(0b1101, highlight(0b0101));
    try testing.expectEqual(0b1110, highlight(0b0110));
    try testing.expectEqual(0b1111, highlight(0b0111));
}

test "highlight leaves upper 8 colors as they were" {
    try testing.expectEqual(0b1000, highlight(0b1000));
    try testing.expectEqual(0b1001, highlight(0b1001));
    try testing.expectEqual(0b1010, highlight(0b1010));
    try testing.expectEqual(0b1011, highlight(0b1011));
    try testing.expectEqual(0b1100, highlight(0b1100));
    try testing.expectEqual(0b1101, highlight(0b1101));
    try testing.expectEqual(0b1110, highlight(0b1110));
    try testing.expectEqual(0b1111, highlight(0b1111));
}

test "highlightByte remaps lower 8 colors to upper 8 colors" {
    try testing.expectEqual(0b1000_1000, highlightByte(0b0000_0000));
    try testing.expectEqual(0b1001_1001, highlightByte(0b0001_0001));
    try testing.expectEqual(0b1010_1010, highlightByte(0b0010_0010));
    try testing.expectEqual(0b1011_1011, highlightByte(0b0011_0011));
    try testing.expectEqual(0b1100_1100, highlightByte(0b0100_0100));
    try testing.expectEqual(0b1101_1101, highlightByte(0b0101_0101));
    try testing.expectEqual(0b1110_1110, highlightByte(0b0110_0110));
    try testing.expectEqual(0b1111_1111, highlightByte(0b0111_0111));
}

test "highlightByte leaves upper 8 colors as they were" {
    try testing.expectEqual(0b1000_1000, highlightByte(0b1000_1000));
    try testing.expectEqual(0b1001_1001, highlightByte(0b1001_1001));
    try testing.expectEqual(0b1010_1010, highlightByte(0b1010_1010));
    try testing.expectEqual(0b1011_1011, highlightByte(0b1011_1011));
    try testing.expectEqual(0b1100_1100, highlightByte(0b1100_1100));
    try testing.expectEqual(0b1101_1101, highlightByte(0b1101_1101));
    try testing.expectEqual(0b1110_1110, highlightByte(0b1110_1110));
    try testing.expectEqual(0b1111_1111, highlightByte(0b1111_1111));
}
