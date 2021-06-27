/// A raw video buffer identifier as represented in Another World's bytecode.
pub const Raw = u8;

/// A specific buffer ID from 0 to 3. This is guaranteed to be valid.
pub const Specific = u2;

pub const front_buffer: Raw = 0xFE;
pub const back_buffer: Raw = 0xFF;

// TODO: confirm the order and meaning of front and back buffers.
pub const Enum = union(enum(Raw)) {
    /// Target a specific buffer from 0 to 3.
    specific: Specific,
    /// Target the current front buffer: the buffer that was rendered to the screen last frame.
    front_buffer,
    /// Target the current back buffer: the buffer that will be drawn this frame.
    back_buffer,
};

pub const Error = error{
    /// Bytecode specified an invalid channel ID.
    InvalidBufferID,
};

pub fn parse(raw: Raw) Error!Enum {
    return switch (raw) {
        0...3 => .{ .specific = @truncate(Specific, raw) },
        front_buffer => .front_buffer,
        back_buffer => .back_buffer,
        else => error.InvalidBufferID,
    };
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse correctly parses raw buffer ID" {
    try testing.expectEqual(.{ .specific = 0 }, parse(0));
    try testing.expectEqual(.{ .specific = 1 }, parse(1));
    try testing.expectEqual(.{ .specific = 2 }, parse(2));
    try testing.expectEqual(.{ .specific = 3 }, parse(3));
    try testing.expectEqual(.front_buffer, parse(0xFE));
    try testing.expectEqual(.back_buffer, parse(0xFF));

    try testing.expectError(error.InvalidBufferID, parse(4));
    try testing.expectError(error.InvalidBufferID, parse(0xFD));
}
