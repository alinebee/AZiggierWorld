/// A raw channel identifier as represented in Another World's bytecode.
pub const Raw = u8;

/// The channel on which to play a sound effect.
pub const Enum = enum(Raw) {
    one,
    two,
    three,
    four,
};

pub const Error = error{
    /// Bytecode specified an invalid channel ID.
    InvalidChannel,
};

pub fn parse(raw: Raw) Error!Enum {
    if (raw > @enumToInt(Enum.four)) {
        return error.InvalidChannel;
    }
    return @intToEnum(Enum, raw);
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "parse returns expected enum cases" {
    testing.expectEqual(.one,   parse(0));
    testing.expectEqual(.two,   parse(1));
    testing.expectEqual(.three, parse(2));
    testing.expectEqual(.four,  parse(3));

    testing.expectError(error.InvalidChannel, parse(4));
}
