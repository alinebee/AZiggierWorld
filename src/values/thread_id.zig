const intToEnum = @import("../utils/introspection.zig").intToEnum;

const Trusted = u6;

/// The ID of a thread as a value from 0-63. Guaranteed to be valid at compile time.
pub const ThreadID = enum(Trusted) {
    /// The main thread: the only thread activated at the start of every bytecode program.
    main = 0,
    // Also allow arbitrary thread IDs from 1-63.
    _,

    /// Given a raw bytecode value, return a trusted thread ID.
    /// Returns InvalidThreadID error if the value is out of range.
    pub fn parse(raw_id: Raw) Error!ThreadID {
        return intToEnum(ThreadID, raw_id) catch error.InvalidThreadID;
    }

    /// Cast a known in-range value to a ThreadID case.
    pub fn cast(raw_id: Trusted) ThreadID {
        return @intToEnum(ThreadID, raw_id);
    }

    /// Returns the ThreadID as an array index.
    pub fn index(id: ThreadID) usize {
        return @enumToInt(id);
    }

    /// The raw ID of a thread as stored in bytecode as an 8-bit unsigned integer.
    /// This can potentially be out of range.
    pub const Raw = u8;

    pub const Error = error{
        /// Bytecode specified an invalid thread ID.
        InvalidThreadID,
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const static_limits = @import("../static_limits.zig");

test "Trusted type matches range of legal thread IDs" {
    try static_limits.validateTrustedType(Trusted, static_limits.thread_count);
}

test "parse succeeds with integer at lower bound" {
    try testing.expectEqual(.main, ThreadID.parse(0x0));
}

test "parse succeeds with integer at higher bound" {
    try testing.expectEqual(ThreadID.cast(0x1), ThreadID.parse(0x1));
}

test "parse returns InvalidThreadID with out-of-bounds integer" {
    try testing.expectError(error.InvalidThreadID, ThreadID.parse(0x40));
}
