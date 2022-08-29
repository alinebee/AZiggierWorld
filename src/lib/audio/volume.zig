const anotherworld = @import("../anotherworld.zig");
const static_limits = anotherworld.static_limits;
const meta = @import("utils").meta;

const max_volume = 64;

/// A volume value that is guaranteed to be in range.
pub const Trusted = u6;
/// A raw volume value as represented in Another World bytecode.
pub const Raw = u8;

pub fn parse(raw: anytype) ParseError!Trusted {
    return meta.intCast(Trusted, raw) catch error.VolumeOutOfRange;
}

pub const ParseError = error{
    /// A volume amount exceeded
    VolumeOutOfRange,
};

// -- Tests --

const testing = @import("utils").testing;

test "Trusted covers legal range of volume values" {
    try static_limits.validateTrustedType(Trusted, max_volume);
}

test "parse returns trusted volume for in-range values" {
    try testing.expectEqual(0, parse(@as(usize, 0)));
    try testing.expectEqual(63, parse(@as(usize, 63)));
}

test "parse returns VolumeOutOfRange for out-of-range values" {
    try testing.expectError(error.VolumeOutOfRange, parse(@as(usize, 64)));
}
