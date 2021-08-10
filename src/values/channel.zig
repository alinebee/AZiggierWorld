const intCast = @import("../utils/introspection.zig").intCast;

/// The identifier of an audio channel as a value from 0-3. Guaranteed at compile-time to be valid.
pub const Trusted = u2;

/// A raw audio channel identifier as represented in Another World's bytecode.
pub const Raw = u8;

pub const Error = error{
    /// Bytecode specified an invalid channel ID.
    InvalidChannel,
};

pub fn parse(raw: Raw) Error!Trusted {
    return intCast(Trusted, raw) catch error.InvalidChannel;
}

// -- Tests --

const testing = @import("../utils/testing.zig");
const static_limits = @import("../static_limits.zig");

test "Trusted type covers range of legal channels" {
    try static_limits.validateTrustedType(Trusted, static_limits.channel_count);
}

test "parse returns expected enum cases" {
    try testing.expectEqual(0, parse(0));
    try testing.expectEqual(1, parse(1));
    try testing.expectEqual(2, parse(2));
    try testing.expectEqual(3, parse(3));

    try testing.expectError(error.InvalidChannel, parse(4));
}
