//! Defines helper methods for readers of RLE-encoded data.
//! These methods are shared between the real reader implementation
//! (see reader.zig) and the mock used in tests (see mock_reader.zig).

const std = @import("std");
const assert = std.debug.assert;
const trait = std.meta.trait;

const introspection = @import("../utils/introspection.zig");

/// Returns a struct of methods that can be mixed into the specified type.
/// Intended usage:
///   const ReaderMethods = @import("reader_methods.zig");
///
///   const ReaderType = struct {
///       usingnamespace ReaderMethods.Mixin(@This());
///   }
///
pub fn Mixin(comptime Self: type) type {
    const ReadError = introspection.ErrorType(Self.readBit);

    return struct {
        /// Returns a raw byte constructed by consuming 8 bits from the underlying reader.
        /// Returns an error if the required bits could not be read.
        pub fn readByte(self: *Self) ReadError!u8 {
            return self.readInt(u8);
        }

        /// Returns an unsigned integer constructed by consuming bits from the underlying reader
        /// up to the integer's width: e.g. readInt(u7) will consume 7 bits.
        /// Returns an error if the required bits could not be read.
        pub fn readInt(self: *Self, comptime Integer: type) ReadError!Integer {
            comptime assert(trait.isUnsignedInt(Integer));

            var value: Integer = 0;
            // TODO: This could be an inline-while: benchmark this to see if that helps.
            var bits_remaining: usize = introspection.bitCount(Integer);
            while (bits_remaining > 0) : (bits_remaining -= 1) {
                value = @shlExact(value, 1);
                value |= try self.readBit();
            }
            return value;
        }
    };
}

// -- Tests --

const testing = @import("../utils/testing.zig");
const MockReader = @import("test_helpers/mock_reader.zig");

test "readInt reads integers of the specified width" {
    // MockReader.new returns a bitwise reader that already includes `ReaderMethods`.
    var parser = MockReader.new(u64, 0xDEAD_BEEF_8BAD_F00D);

    try testing.expectEqual(0xDE, parser.readInt(u8));
    try testing.expectEqual(0xAD, parser.readInt(u8));
    try testing.expectEqual(0xBEEF, parser.readInt(u16));
    try testing.expectEqual(0x8BADF00D, parser.readInt(u32));
    try testing.expectEqual(true, parser.isAtEnd());
}

test "readInt returns error.SourceExhausted when source buffer is too short" {
    var parser = MockReader.new(u8, 0xDE);

    try testing.expectError(error.SourceExhausted, parser.readInt(u16));
    try testing.expectEqual(true, parser.isAtEnd());
}
