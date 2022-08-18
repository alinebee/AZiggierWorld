//! Types for parsing video buffer IDs from Another World bytecode instructions.

const anotherworld = @import("../lib/anotherworld.zig");

const math = @import("std").math;

const _Raw = u8;

pub const BufferID = union(enum(_Raw)) {
    /// Target a specific buffer from 0 to 3.
    specific: Specific,
    /// Target the current front buffer: the buffer that was rendered to the screen last frame.
    front_buffer,
    /// Target the current back buffer: the buffer that will be drawn on the next frame.
    back_buffer,

    pub fn parse(raw: Raw) Error!BufferID {
        return switch (raw) {
            0...math.maxInt(Specific) => .{ .specific = @truncate(Specific, raw) },
            raw_front_buffer => .front_buffer,
            raw_back_buffer => .back_buffer,
            else => error.InvalidBufferID,
        };
    }

    /// A raw video buffer identifier as represented in Another World's bytecode.
    pub const Raw = _Raw;

    /// A specific buffer ID from 0 to 3. Guaranteed at compile-time to be valid.
    pub const Specific = u2;

    pub const Error = error{
        /// Bytecode specified an invalid channel ID.
        InvalidBufferID,
    };

    /// The ID of the front buffer as represented in bytecode.
    pub const raw_front_buffer: Raw = 0xFE;
    /// The ID of the back buffer as represented in bytecode.
    pub const raw_back_buffer: Raw = 0xFF;
};

// -- Tests --

const testing = @import("utils").testing;
const static_limits = anotherworld.static_limits;

test "Specific covers range of legal buffer IDs" {
    try static_limits.validateTrustedType(BufferID.Specific, static_limits.buffer_count);
}

test "parse correctly parses raw buffer ID" {
    try testing.expectEqual(.{ .specific = 0 }, BufferID.parse(0));
    try testing.expectEqual(.{ .specific = 1 }, BufferID.parse(1));
    try testing.expectEqual(.{ .specific = 2 }, BufferID.parse(2));
    try testing.expectEqual(.{ .specific = 3 }, BufferID.parse(3));
    try testing.expectEqual(.front_buffer, BufferID.parse(0xFE));
    try testing.expectEqual(.back_buffer, BufferID.parse(0xFF));

    try testing.expectError(error.InvalidBufferID, BufferID.parse(4));
    try testing.expectError(error.InvalidBufferID, BufferID.parse(0xFD));
}
