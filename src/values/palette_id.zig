//! Each game part in Another World defined a set of 32 16-color palettes,
//! where each palette is indexed in bytecode by an integer from 0-31.
//! The game swapped between palettes from screen to screen or to do effects like lightning or fades.

const anotherworld = @import("../lib/anotherworld.zig");
const intToEnum = anotherworld.meta.intToEnum;

const _Trusted = u5;

/// Represents a palette index from 0-31.
pub const PaletteID = enum(_Trusted) {
    _,

    /// Given a raw byte value, return a palette ID.
    /// Returns error.InvalidPaletteID if the value is out of range.
    pub fn parse(raw_id: Raw) Error!PaletteID {
        return intToEnum(PaletteID, raw_id) catch error.InvalidPaletteID;
    }

    /// Convert a known-to-be-valid integer into a PaletteID.
    pub fn cast(raw_id: anytype) PaletteID {
        return @intToEnum(PaletteID, raw_id);
    }

    /// Convert a Palette ID to an array index.
    pub fn index(id: PaletteID) usize {
        return @enumToInt(id);
    }

    /// A raw palette index stored in bytecode as an 8-bit unsigned integer.
    /// This can potentially be out of range: converted to a PaletteID with `parse`.
    pub const Raw = u8;

    pub const Error = error{
        /// Bytecode specified an invalid palette ID.
        InvalidPaletteID,
    };
};

// -- Tests --

const testing = anotherworld.testing;
const static_limits = anotherworld.static_limits;

test "Trusted covers range of legal palette IDs" {
    try static_limits.validateTrustedType(_Trusted, static_limits.palette_count);
}

test "parse succeeds for in-bounds integers" {
    try testing.expectEqual(PaletteID.cast(0), PaletteID.parse(0b0000_0000));
    try testing.expectEqual(PaletteID.cast(31), PaletteID.parse(0b0001_1111));
}

test "parse returns InvalidPaletteID for out-of-bounds integer" {
    try testing.expectError(error.InvalidPaletteID, PaletteID.parse(0b0010_0000));
}
