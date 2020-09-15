/// A color index from 0-15. This is guaranteed to be valid.
pub const Trusted = u4;

/// A raw color index stored in bytecode as an 8-bit unsigned integer.
/// This can potentially be out of range: converted to a trusted ColorID with `parse`.
pub const Raw = u8;

/// The maximum legal value for a color ID.
const max: Trusted = 0b1111;

pub const Error = error{
    /// Bytecode specified an invalid color ID.
    InvalidColorID,
};

/// Given a raw byte value, return a trusted color ID.
/// Returns InvalidColorID error if the value is out of range.
pub fn parse(raw_id: Raw) Error!Trusted {
    if (raw_id > max) return error.InvalidColorID;
    return @intCast(Trusted, raw_id);
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "parse succeeds for in-bounds integer" {
    testing.expectEqual(15, parse(0b0000_1111));
}

test "parse returns InvalidThreadID for out-of-bounds integer" {
    testing.expectError(error.InvalidColorID, parse(0b0001_0000));
}
