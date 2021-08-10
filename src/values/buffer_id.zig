//! Types for parsing video buffer IDs from Another World bytecode instructions.

const math = @import("std").math;

/// A raw video buffer identifier as represented in Another World's bytecode.
pub const Raw = u8;

/// A specific buffer ID from 0 to 3. Guaranteed at compile-time to be valid.
pub const Specific = u2;

/// The ID of the front buffer as represented in bytecode.
pub const raw_front_buffer: Raw = 0xFE;
/// The ID of the back buffer as represented in bytecode.
pub const raw_back_buffer: Raw = 0xFF;

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
        0...math.maxInt(Specific) => .{ .specific = @truncate(Specific, raw) },
        raw_front_buffer => .front_buffer,
        raw_back_buffer => .back_buffer,
        else => error.InvalidBufferID,
    };
}

// -- Tests --

const testing = @import("../utils/testing.zig");
const static_limits = @import("../static_limits.zig");

test "Specific covers range of legal buffer IDs" {
    try static_limits.validateTrustedType(Specific, static_limits.buffer_count);
}

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
