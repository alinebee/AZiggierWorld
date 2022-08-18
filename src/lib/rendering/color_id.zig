//! Another World used 16-color palettes where each color is indexed by an integer from 0-15.
//! These color IDs appear in bytecode, polygon resources and video buffers.

const anotherworld = @import("../anotherworld.zig");
const intToEnum = @import("utils").meta.intToEnum;

/// A color index from 0-15. Guaranteed at compile-time to be valid.
const _Trusted = u4;

pub const ColorID = enum(_Trusted) {
    _,

    /// Given a raw bytecode value, return a valid color ID.
    /// Returns error.InvalidColorID if the value is out of range.
    pub fn parse(raw_id: Raw) Error!ColorID {
        return intToEnum(ColorID, raw_id) catch error.InvalidColorID;
    }

    /// Cast a known-valid color value to a color ID.
    pub fn cast(raw_id: Trusted) ColorID {
        return @intToEnum(ColorID, raw_id);
    }

    /// Return the color ID as an array index.
    pub fn index(id: ColorID) usize {
        return @enumToInt(id);
    }

    /// Remap colors 0...7 to colors 8...15. Colors 8...15 will be left as they are.
    /// The last 8 colors in a palette are expected to be a lightened/darkened version of the first 8 colors;
    /// Ramping them achieves translucency effects like e.g. the headlights of the ferrari in the game intro.
    pub fn highlight(id: ColorID) ColorID {
        return @intToEnum(ColorID, @enumToInt(id) | 0b1000);
    }

    /// Given a byte containing two 4-bit color IDs, remaps both colors from 0...7 to 8...15.
    /// Colors 8...15 will be left as they are. See `highlight` for more details.
    pub fn highlightByte(color_byte: u8) u8 {
        return color_byte | 0b1000_1000;
    }

    /// A guaranteed-in-range color value.
    pub const Trusted = u4;

    /// A raw color index stored in bytecode as an 8-bit unsigned integer.
    /// This can potentially be out of range: convert to a ColorID with `parse`.
    pub const Raw = u8;

    pub const Error = error{
        /// Bytecode specified an invalid color ID.
        InvalidColorID,
    };
};

// -- Tests --

const testing = @import("utils").testing;
const static_limits = anotherworld.static_limits;

test "Trusted covers range of legal color IDs" {
    try static_limits.validateTrustedType(_Trusted, static_limits.color_count);
}

test "parse succeeds for in-bounds integer" {
    try testing.expectEqual(ColorID.cast(0), ColorID.parse(0b0000_0000));
    try testing.expectEqual(ColorID.cast(15), ColorID.parse(0b0000_1111));
}

test "parse returns InvalidThreadID for out-of-bounds integer" {
    try testing.expectError(error.InvalidColorID, ColorID.parse(0b0001_0000));
}

test "highlight remaps lower 8 colors to upper 8 colors" {
    try testing.expectEqual(ColorID.cast(0b1000), ColorID.cast(0b0000).highlight());
    try testing.expectEqual(ColorID.cast(0b1001), ColorID.cast(0b0001).highlight());
    try testing.expectEqual(ColorID.cast(0b1010), ColorID.cast(0b0010).highlight());
    try testing.expectEqual(ColorID.cast(0b1011), ColorID.cast(0b0011).highlight());
    try testing.expectEqual(ColorID.cast(0b1100), ColorID.cast(0b0100).highlight());
    try testing.expectEqual(ColorID.cast(0b1101), ColorID.cast(0b0101).highlight());
    try testing.expectEqual(ColorID.cast(0b1110), ColorID.cast(0b0110).highlight());
    try testing.expectEqual(ColorID.cast(0b1111), ColorID.cast(0b0111).highlight());
}

test "highlight leaves upper 8 colors as they were" {
    try testing.expectEqual(ColorID.cast(0b1000), ColorID.cast(0b1000).highlight());
    try testing.expectEqual(ColorID.cast(0b1001), ColorID.cast(0b1001).highlight());
    try testing.expectEqual(ColorID.cast(0b1010), ColorID.cast(0b1010).highlight());
    try testing.expectEqual(ColorID.cast(0b1011), ColorID.cast(0b1011).highlight());
    try testing.expectEqual(ColorID.cast(0b1100), ColorID.cast(0b1100).highlight());
    try testing.expectEqual(ColorID.cast(0b1101), ColorID.cast(0b1101).highlight());
    try testing.expectEqual(ColorID.cast(0b1110), ColorID.cast(0b1110).highlight());
    try testing.expectEqual(ColorID.cast(0b1111), ColorID.cast(0b1111).highlight());
}

test "highlightByte remaps lower 8 colors to upper 8 colors" {
    try testing.expectEqual(0b1000_1000, ColorID.highlightByte(0b0000_0000));
    try testing.expectEqual(0b1001_1001, ColorID.highlightByte(0b0001_0001));
    try testing.expectEqual(0b1010_1010, ColorID.highlightByte(0b0010_0010));
    try testing.expectEqual(0b1011_1011, ColorID.highlightByte(0b0011_0011));
    try testing.expectEqual(0b1100_1100, ColorID.highlightByte(0b0100_0100));
    try testing.expectEqual(0b1101_1101, ColorID.highlightByte(0b0101_0101));
    try testing.expectEqual(0b1110_1110, ColorID.highlightByte(0b0110_0110));
    try testing.expectEqual(0b1111_1111, ColorID.highlightByte(0b0111_0111));
}

test "highlightByte leaves upper 8 colors as they were" {
    try testing.expectEqual(0b1000_1000, ColorID.highlightByte(0b1000_1000));
    try testing.expectEqual(0b1001_1001, ColorID.highlightByte(0b1001_1001));
    try testing.expectEqual(0b1010_1010, ColorID.highlightByte(0b1010_1010));
    try testing.expectEqual(0b1011_1011, ColorID.highlightByte(0b1011_1011));
    try testing.expectEqual(0b1100_1100, ColorID.highlightByte(0b1100_1100));
    try testing.expectEqual(0b1101_1101, ColorID.highlightByte(0b1101_1101));
    try testing.expectEqual(0b1110_1110, ColorID.highlightByte(0b1110_1110));
    try testing.expectEqual(0b1111_1111, ColorID.highlightByte(0b1111_1111));
}
