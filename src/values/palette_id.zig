//! Each game part in Another World defined a set of 32 16-color palettes,
//! where each palette is indexed in bytecode by an integer from 0-31.
//! The game swapped between palettes from screen to screen or to do effects like lightning or fades.

/// A palette index from 0-31. This is guaranteed to be valid.
pub const Trusted = u5;

/// A raw palette index stored in bytecode as an 8-bit unsigned integer.
/// This can potentially be out of range: converted to a Trusted ID with `parse`.
pub const Raw = u8;

/// The maximum legal value for a palette ID.
const max: Trusted = 0b11111;

pub const Error = error{
    /// Bytecode specified an invalid color ID.
    InvalidPaletteID,
};

/// Given a raw byte value, return a trusted palette ID.
/// Returns error.InvalidPaletteID if the value is out of range.
pub fn parse(raw_id: Raw) Error!Trusted {
    if (raw_id > max) return error.InvalidPaletteID;
    return @truncate(Trusted, raw_id);
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse succeeds for in-bounds integers" {
    testing.expectEqual(0, parse(0b0000_0000));
    testing.expectEqual(31, parse(0b0001_1111));
}

test "parse returns InvalidThreadID for out-of-bounds integer" {
    testing.expectError(error.InvalidPaletteID, parse(0b0010_0000));
}
