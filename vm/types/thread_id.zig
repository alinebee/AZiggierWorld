/// The ID of a thread, as a value from 0-63.
pub const ThreadID = u6;

/// The raw ID of a thread as stored in bytecode as an 8-bit unsigned integer.
pub const RawThreadID = u8;

/// The total number of available threads.
pub const count = 64;

/// The maximum value for a raw thread ID.
pub const max = count - 1;

pub const Error = error {
    InvalidThreadID,
};

/// Given a raw byte value, return a valid thread ID.
/// Returns InvalidThreadID error if the value is out of range.
pub fn parse(raw_id: u8) Error!ThreadID {
    if (raw_id > max) return error.InvalidThreadID;
    return @intCast(ThreadID, raw_id);
}

// -- Tests --

const testing = @import("std").testing;

test "parse succeeds with in-bounds integer" {
    testing.expectEqual(try parse(0x3F), 0x3F);
}

test "parse returns InvalidThreadID with out-of-bounds integer" {
    testing.expectError(error.InvalidThreadID, parse(max + 1));
}
