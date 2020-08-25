/// The ID of a thread, stored in bytecode as an 8-bit unsigned integer from 0-63.
pub const ThreadID = u6;

pub const Error = error {
    InvalidThreadID,
};

/// Given a raw byte value, return a valid thread ID.
/// Returns InvalidThreadID if the value is out of range.
pub fn parseThreadID(raw_id: u8) Error!ThreadID {
    if (raw_id >= 0x40) return Error.InvalidThreadID;
    return @intCast(ThreadID, raw_id);
}

// -- Tests --

const testing = @import("std").testing;

test "parseThreadID succeeds with in-bounds integer" {
    testing.expectEqual(parseThreadID(0x3F) catch unreachable, 0x3F);
}

test "parseThreadID returns InvalidThreadID with out-of-bounds integer" {
    testing.expectError(Error.InvalidThreadID, parseThreadID(0x40));
}
