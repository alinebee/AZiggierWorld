const std = @import("std");
const assert = std.debug.assert;
const trait = std.meta.trait;

/// Wraps a bitwise reader in an interface that adds methods to read integers of arbitrary sizes.
/// The underlying reader is expected to implement `readBit() !u8` and `validateAfterDecoding() !error`.
pub fn new(underlying_reader: anytype) Instance(@TypeOf(underlying_reader)) {
    return Instance(@TypeOf(underlying_reader)) { .underlying_reader = underlying_reader };
}

pub fn Instance(comptime Wrapped: type) type {
    const ReadBitError = @TypeOf(Wrapped.readBit).ReturnType.ErrorSet;
    const ValidationError = @TypeOf(Wrapped.validateAfterDecoding).ReturnType.ErrorSet;

    return struct {
        const Self = @This();

        underlying_reader: Wrapped,

        /// Read a single bit from the underlying reader.
        pub fn readBit(self: *Self) ReadBitError!u1 {
            return self.underlying_reader.readBit();
        }

        /// Returns a raw byte constructed by consuming 8 bits from the underlying reader.
        /// Returns an error if the required bits could not be read.
        pub fn readByte(self: *Self) ReadBitError!u8 {
            return self.readInt(u8);
        }
        
        /// Returns an unsigned integer constructed by consuming bits from the underlying reader
        /// up to the integer's width: e.g. readInt(u7) will consume 7 bits.
        /// Returns an error if the required bits could not be read.
        pub fn readInt(self: *Self, comptime Integer: type) ReadBitError!Integer {
            comptime assert(trait.isUnsignedInt(Integer));

            var value: Integer = 0;
            // TODO: This could be an inline-while: benchmark this to see if that helps.
            var bits_remaining: usize = Integer.bit_count;
            while (bits_remaining > 0) : (bits_remaining -= 1) {
                value = @shlExact(value, 1);
                value |= try self.underlying_reader.readBit();
            }
            return value;
        }

        /// The expected size of the data once uncompressed.
        pub fn uncompressedSize(self: Self) usize {
            return self.underlying_reader.uncompressed_size;
        }

        /// Whether the underlying reader has consumed all bits.
        pub fn isAtEnd(self: Self) bool {
            return self.underlying_reader.isAtEnd();
        }

        /// Call once decoding is complete to verify that the underlying reader decoded all its data successfully.
        pub fn validateAfterDecoding(self: Self) ValidationError!void {
            return self.underlying_reader.validateAfterDecoding();
        }
    };
}

// -- Tests --

const testing = @import("../utils/testing.zig");
const MockReader = @import("test_helpers/mock_reader.zig");

test "readInt reads integers of the specified width" {
    // MockReader.new returns a bitwise reader that's already wrapped in a `ReaderInterface`.
    var parser = MockReader.new(u64, 0xDEAD_BEEF_0BAD_F00D);

    testing.expectEqual(0xDE, parser.readInt(u8));
    testing.expectEqual(0xAD, parser.readInt(u8));
    testing.expectEqual(0xBEEF, parser.readInt(u16));
    testing.expectEqual(0x0BADF00D, parser.readInt(u32));
    testing.expectEqual(true, parser.isAtEnd());
}

test "readInt returns error.SourceBufferEmpty when source buffer is too short" {
    var parser = MockReader.new(u8, 0xDE);

    testing.expectError(error.SourceBufferEmpty, parser.readInt(u16));
    testing.expectEqual(true, parser.isAtEnd());
}
