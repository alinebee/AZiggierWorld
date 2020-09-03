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
    return struct {
        const Self = @This();

        reader: ReaderType,

        /// Read the next run-length encoding instruction from the reader.
        /// Returns an error if data could not be read fully.
        pub fn readInstruction(self: *Self) !Instruction {
            switch (try self.reader.readBit()) {
                0b1 => {
                    switch (try self.readInt(2)) {
                        0b11 => {
                            // 111|cccc_cccc
                            // next 8 bits are count: copy the following `count + 9` bytes of data
                            const count = try self.readInt(8);
                            return Instruction { .write_from_compressed = count + 9 };
                        },
                        0b10 => {
                            // 110|cccc_cccc|oooo_oooo_oooo
                            // next 8 bits are count, next 12 bits are relative offset within uncompressed data:
                            // copy `count + 1` bytes from uncompressed data at offset
                            const count = try self.readInt(8);
                            const offset = try self.readInt(12);
                            return Instruction { .copy_from_uncompressed = .{
                                .count = count + 1,
                                .offset = offset,
                            } };
                        },
                        0b01 => {
                            // 101|oooo_oooo_oo
                            // next 10 bits are relative offset within uncompressed data:
                            // copy 4 bytes from uncompressed data at offset
                            const offset = try self.readInt(10);
                            return Instruction { .copy_from_uncompressed = .{
                                .count = 4,
                                .offset = offset,
                            } };
                        },
                        0b00 => {
                            // 100|oooo_oooo_o
                            // next 9 bits are relative offset: copy 3 bytes from uncompressed data at offset
                            const offset = try self.readInt(9);
                            return Instruction { .copy_from_uncompressed = .{
                                .count = 3,
                                .offset = offset,
                            } };
                        },
                        else => unreachable,
                    }
                },
                0b0 => {
                    switch (try self.reader.readBit()) {
                        0b1 => {
                            // 01|oooo_oooo
                            // next 8 bits are relative offset: copy 2 bytes from uncompressed data at offset
                            const offset = try self.readInt(8);
                            return Instruction { .copy_from_uncompressed = .{
                                .count = 2,
                                .offset = offset,
                            } };
                        },
                        0b0 => {
                            // 00|ccc
                            // next 3 bits are count: copy the next (count + 1) bytes of packed data
                            const count = try self.readInt(3);
                            return Instruction { .write_from_compressed = count + 1 };
                        },
                    }
                    unreachable;
                },
            }
        }

        /// Reads a run of bytes from the reader into the specified destination buffer.
        /// Returns an error if data could not be read fully; in this situation,
        /// `destination` may contain partial data.
        pub fn readBytes(self: *Self, destination: []u8) !void {
            var index: usize = 0;
            while (index < destination.len) : (index += 1) {
                destination[index] = @truncate(u8, try self.readInt(8));
            }
        }
        
        /// Reads the specified number of bits from the reader into an unsigned integer.
        /// Returns an error if the required bits could not be read.
        fn readInt(self: *Self, comptime bit_count: usize) !usize {
            comptime assert(bit_count <= usize.bit_count);

            var value: usize = 0;
            // TODO: This could be an inline-while: benchmark this to see if that helps.
            var bits_remaining: usize = bit_count;
            while (bits_remaining > 0) : (bits_remaining -= 1) {
                value <<= 1;
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

// -- Test helpers --

const testing = @import("../../utils/testing.zig");

/// Real run-length-encoded data is stored backwards and has checksums to worry about,
/// and so is exceedingly cumbersome to set up fake fixture data for.
/// This is a simplified reader that walks through an array of bytes bit by bit from start to end.
const TestReader = struct {
    bytes: []const u8,
    counter: usize = 0,

    fn readBit(self: *TestReader) !u1 {
        const byte_index = self.counter / 8;
        const bit_index = @intCast(u3, self.counter % 8);

        if (byte_index >= self.bytes.len) {
            return error.EndOfStream;
        }

        self.counter += 1;

        // Walk through the bits from highest to lowest to preserve definition order
        const shift = 7 - bit_index;
        return @truncate(u1, self.bytes[byte_index] >> shift);
    }
};

test "TestReader.readBit reads all bits in order from highest to lowest" {
    const bytes = [_]u8 { 0b1001_0110 };

    var reader = TestReader { .bytes = &bytes };
    for ([_]u1 { 1, 0, 0, 1, 0, 1, 1, 0 }) |bit| {
        testing.expectEqual(bit, reader.readBit());
    }
}

test "TestReader.readBit returns error.EndOfStream when it runs out of bits" {
    const bytes = [_]u8 { };

    var reader = TestReader { .bytes = &bytes };
    testing.expectError(error.EndOfStream, reader.readBit());
}

// -- Tests --

test "Instance.readInt reads integers of the specified width" {
    const source = [_]u8 { 
        0xDE, 0xAD, 0xBE, 0xEF, 
        0x0B, 0xAD, 0xF0, 0x0D,
    };

    var parser = new(TestReader { .bytes = &source });

    testing.expectEqual(0xDE, parser.readInt(8));
    testing.expectEqual(0xAD, parser.readInt(8));
    testing.expectEqual(0xBEEF, parser.readInt(16));
    testing.expectEqual(0x0BADF00D, parser.readInt(32));
}

test "Instance.readInt returns error.EndOfStream when source buffer is too short" {
    const source = [_]u8 { 0xDE };

    var parser = new(TestReader { .bytes = &source });

    testing.expectError(error.EndOfStream, parser.readInt(16));
}

test "Instance.readBytes reads expected bytes" {
    const source = [_]u8 { 
        0xDE, 0xAD, 0xBE, 0xEF,
        0x0B, 0xAD, 0xF0, 0x0D,
    };

    var destination: [8]u8 = undefined;
    
    var parser = new(TestReader { .bytes = &source });

    try parser.readBytes(destination[0..8]);
    testing.expectEqualSlices(u8, &source, &destination);
}

test "Instance.readBytes returns error.EndOfStream when source buffer is too short" {
    const source = [_]u8 { 
        0xDE, 0xAD, 0xBE, 0xEF,
        0x0B, 0xAD, 0xF0,
    };

    var destination: [8]u8 = undefined;
    
    var parser = new(TestReader { .bytes = &source });

    testing.expectError(error.EndOfStream, parser.readBytes(destination[0..8]));
}

test "Instance.readInstruction parses 111 instruction" {
    // 111|cccc_cccc: 11 bits total
    // next 8 bits are count: copy the next (count + 9) bytes of packed data immediately after this.
    const source = [_]u8 {
        0b111_0111_1, 0b101_00000,
    };

    var parser = new(TestReader { .bytes = &source });
    testing.expectEqual(
        Instruction { .write_from_compressed = 0b0111_1101 + 9 },
        parser.readInstruction(),
    );
}

test "Instance.readInstruction parses 110 instruction" {
    // 110|cccc_cccc|oooo_oooo_oooo: 23 bits total
    // next 8 bits are count, next 12 bits are relative offset within uncompressed data:
    // copy (count + 1) bytes from the uncompressed data at that offset.
    const source = [_]u8 {
        0b110_0111_1, 0b101_1101_1, 0b001_1010_0,
    };

    var parser = new(TestReader { .bytes = &source });
    testing.expectEqual(
        Instruction { .copy_from_uncompressed = .{
            .count = 0b0111_1101 + 1,
            .offset = 0b1101_1001_1010,
        } },
        parser.readInstruction(),
    );
}

test "Instance.readInstruction parses 101 instruction" {
    // 101|oooo_oooo_oo: 13 bits total
    // next 10 bits are relative offset: copy 4 bytes from uncompressed data at offset.
    const source = [_]u8 {
        0b101_0111_1, 0b101_11_000,
    };

    var parser = new(TestReader { .bytes = &source });
    testing.expectEqual(
        Instruction { .copy_from_uncompressed = .{
            .count = 4,
            .offset = 0b0111_1101_11,
        } },
        parser.readInstruction(),
    );
}

test "Instance.readInstruction parses 100 instruction" {
    // 100|oooo_oooo_o: 12 bits total
    // next 9 bits are relative offset: copy 3 bytes from uncompressed data at offset.
    const source = [_]u8 {
        0b100_0111_1, 0b101_1_0000,
    };

    var parser = new(TestReader { .bytes = &source });
    testing.expectEqual(
        Instruction { .copy_from_uncompressed = .{
            .count = 3,
            .offset = 0b0111_1101_1,
        } },
        parser.readInstruction(),
    );
}

test "Instance.readInstruction parses 01 instruction" {
    // 01|oooo_oooo: 10 bits total
    // next 8 bits are relative offset: copy 2 bytes from uncompressed data at offset.
    const source = [_]u8 {
        0b01_0111_11, 0b01_000000,
    };

    var parser = new(TestReader { .bytes = &source });
    testing.expectEqual(
        Instruction { .copy_from_uncompressed = .{
            .count = 2,
            .offset = 0b0111_1101,
        } },
        parser.readInstruction(),
    );
}

test "Instance.readInstruction parses 00 instruction" {
    // 00|ccc: 5 bits total
    // next 3 bits are count: copy the next (count + 1) bytes immediately after the instruction.
    const source = [_]u8 {
        0b00_110_000,
    };

    var parser = new(TestReader { .bytes = &source });
    testing.expectEqual(
        Instruction { .write_from_compressed = 0b110 + 1 },
        parser.readInstruction(),
    );
}