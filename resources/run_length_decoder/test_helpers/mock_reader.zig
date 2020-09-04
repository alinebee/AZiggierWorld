const std = @import("std");
const Log2Int = std.math.Log2Int;
const assert = std.debug.assert;
const trait = std.meta.trait;

/// Returns a mock bitwise reader that reads every bit from a specified integer value
/// in order from left to right (highest to lowest).
///
/// `Integer` is any unsigned integer type, whose width is the total number
/// of bits that will be read: e.g. `intReader(u7, bits)` will return 7 bits in total.
/// `bits` is an integer storing the actual bits to read.
///
/// If `Integer` is wider than is needed to store `bits`,
/// the bits will be left-padded with zeroes out to the full width.
/// e.g. `intReader(u5, 0b110)` would return 0, 0, 1, 1, 0.
pub fn new(comptime Integer: type, bits: Integer) Instance(Integer) {
    return Instance(Integer) { .bits = bits };
}

fn Instance(comptime Integer: type) type {
    comptime assert(trait.isUnsignedInt(Integer));

    comptime const ShiftType = Log2Int(Integer);
    comptime const max_shift = Integer.bit_count - 1;

    return struct {
        const Self = @This();

        bits: Integer,
        count: usize = 0,

        pub fn readBit(self: *Self) Error!u1 {
            if (self.isAtEnd()) {
                return error.EndOfStream;
            }

            const shift = @intCast(ShiftType, max_shift - self.count);
            self.count += 1;

            return @truncate(u1, self.bits >> shift);
        }

        pub fn isAtEnd(self: Self) bool {
            return self.count >= Integer.bit_count;
        }
    };
}

/// All possible errors produced by the mock bitwise reader.
pub const Error = error {
    EndOfStream,
};

// -- Tests --

const testing = @import("../../../utils/testing.zig");

test "readBit reads all bits in order from highest to lowest" {
    var reader = new(u8, 0b1001_0110);
    const expected = [_]u1 { 1, 0, 0, 1, 0, 1, 1, 0 };
    
    for (expected) |bit| {
        testing.expectEqual(bit, reader.readBit());
    }
    testing.expect(reader.isAtEnd());
}

test "readBit is left-padded" {
    var reader = new(u5, 0b110);
    const expected = [_]u1 { 0, 0, 1, 1, 0 };

    for (expected) |bit| {
        testing.expectEqual(bit, reader.readBit());
    }
    testing.expect(reader.isAtEnd());
}

test "readBit returns error.EndOfStream once it runs out of bits" {
    var reader = new(u1, 1);
    testing.expectEqual(1, reader.readBit());
    testing.expectError(error.EndOfStream, reader.readBit());
    testing.expect(reader.isAtEnd());
}
