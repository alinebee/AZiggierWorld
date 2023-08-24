//! Defines helper methods for readers of RLE-encoded data.
//! These methods are shared between the real reader implementation
//! (see reader.zig) and the mock used in tests (see mock_reader.zig).

const meta = @import("utils").meta;

const std = @import("std");
const assert = std.debug.assert;
const trait = std.meta.trait;

/// Wraps an underlying run-length-encoded reader in a standard interface.
pub fn reader(reader: anytype) ReaderInterface(@typeOf(reader)) {
    return ReaderInterface(@typeOf(reader)){ .reader = reader };
}

pub fn ReaderInterface(comptime Reader: type) type {
    return struct {
        /// The underlying reader for this interface.
        reader: Reader,

        const Self = @This();

        /// The type of error that can be returned from a call to any method in this interface.
        const ReadError = meta.ErrorType(Reader.readBit);

        /// Reads a single bit from the underlying reader.
        pub fn readBit(self: *Self) ReadError!u1 {
            return try self.reader.readBit();
        }

        pub fn isAtEnd(self: Self) bool {
            return self.reader.isAtEnd();
        }

        /// Returns an unsigned integer constructed by consuming bits from the underlying reader
        /// up to the integer's width: e.g. readInt(u7) will consume 7 bits.
        /// Returns an error if the required bits could not be read.
        pub fn readInt(self: *Self, comptime Integer: type) ReadError!Integer {
            comptime assert(trait.isUnsignedInt(Integer));

            var value: Integer = 0;
            // TODO: This could be an inline-while: benchmark this to see if that helps.
            var bits_remaining: usize = meta.bitCount(Integer);
            while (bits_remaining > 0) : (bits_remaining -= 1) {
                value = @shlExact(value, 1);
                value |= try self.reader.readBit();
            }
            return value;
        }

        /// Returns a raw byte constructed by consuming 8 bits from the underlying reader.
        /// Returns an error if the required bits could not be read.
        pub fn readByte(self: *Self) ReadError!u8 {
            return self.readInt(u8);
        }
    };
}

// -- Tests --

const testing = @import("utils").testing;
const mockReader = @import("test_helpers/mock_reader.zig").mockReader;

test "readInt reads integers of the specified width" {
    var interface = reader(mockReader(u64, 0xDEAD_BEEF_8BAD_F00D));

    try testing.expectEqual(0xDE, interface.readInt(u8));
    try testing.expectEqual(0xAD, interface.readInt(u8));
    try testing.expectEqual(0xBEEF, interface.readInt(u16));
    try testing.expectEqual(0x8BADF00D, interface.readInt(u32));
    try testing.expectEqual(true, interface.isAtEnd());
}

test "readInt returns error.SourceExhausted when source buffer is too short" {
    var interface = reader(mockReader(u8, 0xDE));

    try testing.expectError(error.SourceExhausted, interface.readInt(u16));
    try testing.expectEqual(true, interface.isAtEnd());
}
