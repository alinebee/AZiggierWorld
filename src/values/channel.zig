/// The identifier of an audio channel as a value from 0-3. This is guaranteed to be valid.
pub const Trusted = u2;

/// A raw audio channel identifier as represented in Another World's bytecode.
pub const Raw = u8;

pub const Error = error{
    /// Bytecode specified an invalid channel ID.
    InvalidChannel,
};

/// The maximum legal value for a channel ID.
const max = 0b11;

pub fn parse(raw: Raw) Error!Trusted {
    if (raw > max) return error.InvalidChannel;
    return @truncate(Trusted, raw);
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse returns expected enum cases" {
    testing.expectEqual(0, parse(0));
    testing.expectEqual(1, parse(1));
    testing.expectEqual(2, parse(2));
    testing.expectEqual(3, parse(3));

    testing.expectError(error.InvalidChannel, parse(4));
}
