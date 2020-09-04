//! Another World's run-length encoding system uses several decoding instructions,
//! which are marked by the first 2 or 3 bits of every encoded sequence:
    
//! 111|cccc_cccc: next 8 bits are count: copy the next (count + 9) bytes immediately after this instruction.
//! 110|cccc_cccc|oooo_oooo_oooo: next 8 bits are count, next 12 bits are offset relative to write cursor:
//! copy (count + 1) bytes from the already-uncompressed data at that offset.
//! 101|oooo_oooo_oo: next 10 bits are relative offset: copy 4 bytes from uncompressed data at offset.
//! 100|oooo_oooo_o: next 9 bits are relative offset: copy 3 bytes from uncompressed data at offset.
//! 01|oooo_oooo: next 8 bits are relative offset: copy 2 bytes from uncompressed data at offset.
//! 00|ccc: next 3 bits are count: copy the next (count + 1) bytes immediately after this instruction.

const std = @import("std");
const assert = std.debug.assert;
const trait = std.meta.trait;

/// Construct a new RLE instruction parser that wraps a bitwise reader
/// and reads RLE instructions and raw byte sequences from it.
/// `underlying_reader` must implement a `readBit() !u1` function,
/// which is expected to return `error.EndOfStream` if it runs out of bits.
pub fn new(underlying_reader: anytype) Instance(@TypeOf(underlying_reader)) {
    return .{ .reader = underlying_reader };
}

/// Wraps a bitwise reader in something that can parse whole integers and RLE instructions.
/// Reader is expected to have a `readBit` function, but can otherwise be any type.
pub fn Instance(comptime ReaderType: type) type {
    const reader_errors = @TypeOf(ReaderType.readBit).ReturnType.ErrorSet;

    return struct {
        const Self = @This();

        reader: ReaderType,

        /// Read the next run-length encoding instruction from the reader.
        /// Returns an error if data could not be read fully.
        pub fn readInstruction(self: *Self) reader_errors!Instruction {
            switch (try self.reader.readBit()) {
                0b1 => {
                    switch (try self.readInt(u2)) {
                        0b11 => {
                            // 111|cccc_cccc
                            // next 8 bits are count: copy the following `count + 9` bytes of data
                            const count: usize = try self.readInt(u8);
                            return Instruction { .write_from_compressed = count + 9 };
                        },
                        0b10 => {
                            // 110|cccc_cccc|oooo_oooo_oooo
                            // next 8 bits are count, next 12 bits are relative offset within uncompressed data:
                            // copy `count + 1` bytes from uncompressed data at offset
                            const count: usize = try self.readInt(u8);
                            const offset: usize = try self.readInt(u12);
                            return Instruction { .copy_from_uncompressed = .{
                                .count = count + 1,
                                .offset = offset,
                            } };
                        },
                        0b01 => {
                            // 101|oooo_oooo_oo
                            // next 10 bits are relative offset within uncompressed data:
                            // copy 4 bytes from uncompressed data at offset
                            const offset: usize = try self.readInt(u10);
                            return Instruction { .copy_from_uncompressed = .{
                                .count = 4,
                                .offset = offset,
                            } };
                        },
                        0b00 => {
                            // 100|oooo_oooo_o
                            // next 9 bits are relative offset: copy 3 bytes from uncompressed data at offset
                            const offset: usize = try self.readInt(u9);
                            return Instruction { .copy_from_uncompressed = .{
                                .count = 3,
                                .offset = offset,
                            } };
                        },
                    }
                },
                0b0 => {
                    switch (try self.reader.readBit()) {
                        0b1 => {
                            // 01|oooo_oooo
                            // next 8 bits are relative offset: copy 2 bytes from uncompressed data at offset
                            const offset: usize = try self.readInt(u8);
                            return Instruction { .copy_from_uncompressed = .{
                                .count = 2,
                                .offset = offset,
                            } };
                        },
                        0b0 => {
                            // 00|ccc
                            // next 3 bits are count: copy the next (count + 1) bytes of packed data
                            const count: usize = try self.readInt(u3);
                            return Instruction { .write_from_compressed = count + 1 };
                        },
                    }
                    unreachable;
                },
            }
        }

        /// Reads a raw byte from the reader.
        /// Returns an error if the required bits could not be read.
        pub fn readByte(self: *Self) reader_errors!u8 {
            return self.readInt(u8);
        }
        
        /// Reads bits from the reader into an unsigned integer up to the integer's width:
        /// e.g. readInt(u7) would read 7 bits.
        /// Returns an error if the required bits could not be read.
        fn readInt(self: *Self, comptime Integer: type) reader_errors!Integer {
            comptime assert(trait.isUnsignedInt(Integer));

            var value: Integer = 0;
            // TODO: This could be an inline-while: benchmark this to see if that helps.
            var bits_remaining: usize = Integer.bit_count;
            while (bits_remaining > 0) : (bits_remaining -= 1) {
                value = @shlExact(value, 1);
                value |= try self.reader.readBit();
            }
            return value;
        }
    };
}

/// The set of decoding instructions that can be returned from `readInstruction`.
pub const Instruction = union(enum) {
    /// Read n bytes of compressed data from the current read cursor,
    /// and write them directly to the current destination cursor.
    write_from_compressed: usize,

    /// Read `count` bytes of uncompressed data from `offset` relative to the current destination cursor,
    /// and write them to the current destination cursor.
    copy_from_uncompressed: struct { count: usize, offset: usize },
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const MockReader = @import("test_helpers/mock_reader.zig");

test "Instance.readInt reads integers of the specified width" {
    var parser = new(MockReader.new(u64, 0xDEAD_BEEF_0BAD_F00D));

    testing.expectEqual(0xDE, parser.readInt(u8));
    testing.expectEqual(0xAD, parser.readInt(u8));
    testing.expectEqual(0xBEEF, parser.readInt(u16));
    testing.expectEqual(0x0BADF00D, parser.readInt(u32));
    testing.expect(parser.reader.isAtEnd());
}

test "Instance.readInt returns error.EndOfStream when source buffer is too short" {
    var parser = new(MockReader.new(u8, 0xDE));

    testing.expectError(error.EndOfStream, parser.readInt(u16));
    testing.expect(parser.reader.isAtEnd());
}

test "Instance.readInstruction parses 111 instruction" {
    // 111|cccc_cccc: 11 bits total
    // next 8 bits are count: copy the next (count + 9) bytes of packed data immediately after this.
    var parser = new(MockReader.new(u11, 0b111_0111_1101));

    testing.expectEqual(
        Instruction { .write_from_compressed = 0b0111_1101 + 9 },
        parser.readInstruction(),
    );
    testing.expect(parser.reader.isAtEnd());
}

test "Instance.readInstruction parses 111 instruction with max count without overflowing" {
    var parser = new(MockReader.new(u11, 0b111_1111_1111));
    
    testing.expectEqual(
        Instruction { .write_from_compressed = 0b1111_1111 + 9 },
        parser.readInstruction(),
    );
    testing.expect(parser.reader.isAtEnd());
}

test "Instance.readInstruction parses 110 instruction" {
    // 110|cccc_cccc|oooo_oooo_oooo: 23 bits total
    // next 8 bits are count, next 12 bits are relative offset within uncompressed data:
    // copy (count + 1) bytes from the uncompressed data at that offset.
    var parser = new(MockReader.new(u23, 0b110_0111_1101_1101_1001_1010));

    testing.expectEqual(
        Instruction { .copy_from_uncompressed = .{
            .count = 0b0111_1101 + 1,
            .offset = 0b1101_1001_1010,
        } },
        parser.readInstruction(),
    );
    testing.expect(parser.reader.isAtEnd());
}

test "Instance.readInstruction parses 101 instruction" {
    // 101|oooo_oooo_oo: 13 bits total
    // next 10 bits are relative offset: copy 4 bytes from uncompressed data at offset.
    var parser = new(MockReader.new(u13, 0b101_0111_1101_11));

    testing.expectEqual(
        Instruction { .copy_from_uncompressed = .{
            .count = 4,
            .offset = 0b0111_1101_11,
        } },
        parser.readInstruction(),
    );
    testing.expect(parser.reader.isAtEnd());
}

test "Instance.readInstruction parses 100 instruction" {
    // 100|oooo_oooo_o: 12 bits total
    // next 9 bits are relative offset: copy 3 bytes from uncompressed data at offset.
    var parser = new(MockReader.new(u12, 0b100_0111_1101_1));

    testing.expectEqual(
        Instruction { .copy_from_uncompressed = .{
            .count = 3,
            .offset = 0b0111_1101_1,
        } },
        parser.readInstruction(),
    );
    testing.expect(parser.reader.isAtEnd());
}

test "Instance.readInstruction parses 01 instruction" {
    // 01|oooo_oooo: 10 bits total
    // next 8 bits are relative offset: copy 2 bytes from uncompressed data at offset.
    var parser = new(MockReader.new(u10, 0b01_0111_1101));

    testing.expectEqual(
        Instruction { .copy_from_uncompressed = .{
            .count = 2,
            .offset = 0b0111_1101,
        } },
        parser.readInstruction(),
    );
    testing.expect(parser.reader.isAtEnd());
}

test "Instance.readInstruction parses 00 instruction" {
    // 00|ccc: 5 bits total
    // next 3 bits are count: copy the next (count + 1) bytes immediately after the instruction.
    var parser = new(MockReader.new(u5, 0b00_110));
    
    testing.expectEqual(
        Instruction { .write_from_compressed = 0b110 + 1 },
        parser.readInstruction(),
    );
    testing.expect(parser.reader.isAtEnd());
}