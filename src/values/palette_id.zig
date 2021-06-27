//! Each game part in Another World defined a set of 32 16-color palettes,
//! where each palette is indexed in bytecode by an integer from 0-31.
//! The game swapped between palettes from screen to screen or to do effects like lightning or fades.

const intCast = @import("../utils/introspection.zig").intCast;

/// A palette index from 0-31. This is guaranteed to be valid.
pub const Trusted = u5;

/// A raw palette index stored in bytecode as an 8-bit unsigned integer.
/// This can potentially be out of range: converted to a Trusted ID with `parse`.
pub const Raw = u8;

pub const Error = error{
    /// Bytecode specified an invalid color ID.
    InvalidPaletteID,
};

/// Given a raw byte value, return a trusted palette ID.
/// Returns error.InvalidPaletteID if the value is out of range.
pub fn parse(raw_id: Raw) Error!Trusted {
    return intCast(Trusted, raw_id) catch error.InvalidPaletteID;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse succeeds for in-bounds integers" {
    try testing.expectEqual(0, parse(0b0000_0000));
    try testing.expectEqual(31, parse(0b0001_1111));
}

test "parse returns InvalidThreadID for out-of-bounds integer" {
    try testing.expectError(error.InvalidPaletteID, parse(0b0010_0000));
}
