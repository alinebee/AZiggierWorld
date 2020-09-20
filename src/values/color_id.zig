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

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse succeeds for in-bounds integer" {
    testing.expectEqual(0, parse(0b0000_0000));
    testing.expectEqual(15, parse(0b0000_1111));
}

test "parse returns InvalidThreadID for out-of-bounds integer" {
    testing.expectError(error.InvalidColorID, parse(0b0001_0000));
}
