const intToEnum = @import("../utils/introspection.zig").intToEnum;

const Trusted = u2;

/// The identifier of one of Another World's four audio channels.
pub const ChannelID = enum(Trusted) {
    _,

    /// Convert an integer parsed from Another World bytecode into a valid channel ID.
    /// Returns error.InvalidChannelID if the value was out of range.
    pub fn parse(raw: Raw) Error!ChannelID {
        return intToEnum(ChannelID, raw) catch error.InvalidChannelID;
    }

    /// Convert a known-to-be-valid integer into a valid channel ID.
    pub fn cast(raw: anytype) ChannelID {
        return @intToEnum(ChannelID, raw);
    }

    /// A raw audio channel identifier as represented in Another World's bytecode.
    pub const Raw = u8;

    pub const Error = error{
        /// Bytecode specified an invalid channel ID.
        InvalidChannelID,
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const static_limits = @import("../static_limits.zig");

test "Trusted type covers range of legal channels" {
    try static_limits.validateTrustedType(Trusted, static_limits.channel_count);
}

test "parse returns expected enum cases" {
    try testing.expectEqual(ChannelID.cast(0), ChannelID.parse(0));
    try testing.expectEqual(ChannelID.cast(1), ChannelID.parse(1));
    try testing.expectEqual(ChannelID.cast(2), ChannelID.parse(2));
    try testing.expectEqual(ChannelID.cast(3), ChannelID.parse(3));

    try testing.expectError(error.InvalidChannelID, ChannelID.parse(4));
}
