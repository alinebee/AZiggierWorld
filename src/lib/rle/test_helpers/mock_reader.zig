const anotherworld = @import("../../anotherworld.zig");
const meta = @import("utils").meta;

const std = @import("std");
const assert = std.debug.assert;
const trait = std.meta.trait;

const ReaderMethods = @import("../reader_methods.zig").ReaderMethods;

/// Returns a mock reader that reads every bit from a specified integer value
/// in order from left to right (highest to lowest).
///
/// `Integer` is any unsigned integer type, whose width is the total number
/// of bits that will be read: e.g. `intReader(u7, bits)` will return 7 bits in total.
/// `bits` is an integer storing the actual bits to read.
///
/// If `Integer` is wider than is needed to store `bits`,
/// the bits will be left-padded with zeroes out to the full width.
/// e.g. `intReader(u5, 0b110)` would return 0, 0, 1, 1, 0.
pub fn mockReader(comptime Integer: type, bits: Integer) MockReader(Integer) {
    return MockReader(Integer){ .bits = bits };
}

fn MockReader(comptime Integer: type) type {
    comptime assert(trait.isUnsignedInt(Integer));

    const ShiftType = meta.ShiftType(Integer);
    const bit_count = meta.bitCount(Integer);
    const max_shift: ShiftType = bit_count - 1;

    return struct {
        const Self = @This();

        bits: Integer,
        count: usize = 0,
        uncompressed_size: usize = @sizeOf(Integer),

        pub fn readBit(self: *Self) Error!u1 {
            if (self.isAtEnd()) {
                return error.SourceExhausted;
            }

            const shift = @intCast(ShiftType, max_shift - self.count);
            self.count += 1;

            return @truncate(u1, self.bits >> shift);
        }

        pub fn isAtEnd(self: Self) bool {
            return self.count >= bit_count;
        }

        pub fn validateChecksum(self: Self) Error!void {
            if (self.isAtEnd() == false) {
                return error.ChecksumNotReady;
            }
        }

        // Add methods for reading bytes and whole integers
        usingnamespace ReaderMethods(Self);

        /// All possible errors produced by the mock bitwise reader.
        pub const Error = error{
            /// The reader ran out of bits to consume before decoding was completed.
            SourceExhausted,

            /// Decoding completed before the reader had fully consumed all bits.
            ChecksumNotReady,
        };
    };
}

// -- Tests --

const testing = @import("utils").testing;

test "readBit reads all bits in order from highest to lowest" {
    var reader = mockReader(u8, 0b1001_0110);
    const expected = [_]u1{ 1, 0, 0, 1, 0, 1, 1, 0 };

    for (expected) |bit| {
        try testing.expectEqual(bit, reader.readBit());
    }
    try testing.expectEqual(true, reader.isAtEnd());
}

test "readBit is left-padded" {
    var reader = mockReader(u5, 0b110);
    const expected = [_]u1{ 0, 0, 1, 1, 0 };

    for (expected) |bit| {
        try testing.expectEqual(bit, reader.readBit());
    }
    try testing.expectEqual(true, reader.isAtEnd());
}

test "readBit returns error.SourceExhausted once it runs out of bits" {
    var reader = mockReader(u1, 0b1);
    try testing.expectEqual(1, reader.readBit());
    try testing.expectError(error.SourceExhausted, reader.readBit());
    try testing.expectEqual(true, reader.isAtEnd());
}

test "validateChecksum returns error.ChecksumNotReady if reader hasn't consumed all bits" {
    var reader = mockReader(u1, 0b1);
    try testing.expectError(error.ChecksumNotReady, reader.validateChecksum());
    try testing.expectEqual(false, reader.isAtEnd());
}
