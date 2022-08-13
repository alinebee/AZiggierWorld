//! Defines a function for parsing and executing Another World's run-length encoding (RLE) instructions.
//!
//! Another World's RLE algorithm compressed data using 6 different instructions,
//! which are identified by the first 2 or 3 bits of each instruction sequence:
//!
//! 111|cccc_cccc: next 8 bits are count: write the [count + 9] bytes following this instruction to the write cursor.
//! 110|cccc_cccc|oooo_oooo_oooo: next 8 bits are count, next 12 bits are an offset *relative to the write cursor*:
//! duplicate the [count + 1] already-uncompressed bytes from that offset to the write cursor.
//! 101|oooo_oooo_oo: next 10 bits are relative offset: duplicate 4 bytes from uncompressed data at offset.
//! 100|oooo_oooo_o: next 9 bits are relative offset: duplicate 3 bytes from uncompressed data at offset.
//! 01|oooo_oooo: next 8 bits are relative offset: duplicate 2 bytes from uncompressed data at offset.
//! 00|ccc: next 3 bits are count: write the next [count + 1] bytes following this instruction to the write cursor.

/// Reads the next RLE instruction from the specified reader, and executes the instruction on the specified writer.
/// Returns an error if the reader could not read or the writer could not write.
///
/// `reader` must respond to `readBit() !u1`, `readByte() !u8` and `readInt(T) !T`.
/// `writer` must respond to `writeFromSource(reader, count) !void` and `copyFromDestination(count, offset) !void`.
pub fn decodeInstruction(reader: anytype, writer: anytype) !void {
    switch (try reader.readBit()) {
        0b1 => {
            switch (try reader.readInt(u2)) {
                0b11 => {
                    // 111|cccc_cccc
                    // next 8 bits are count: write the subsequent `count + 9` bytes of raw data
                    const count: usize = try reader.readInt(u8);
                    try writer.writeFromSource(reader, count + 9);
                },
                0b10 => {
                    // 110|cccc_cccc|oooo_oooo_oooo
                    // next 8 bits are count, next 12 bits are relative offset within uncompressed data:
                    // copy `count + 1` bytes from uncompressed data at offset
                    const count: usize = try reader.readInt(u8);
                    const offset: usize = try reader.readInt(u12);
                    try writer.copyFromDestination(count + 1, offset);
                },
                0b01 => {
                    // 101|oooo_oooo_oo
                    // next 10 bits are relative offset within uncompressed data:
                    // copy 4 bytes from uncompressed data at offset
                    const offset: usize = try reader.readInt(u10);
                    try writer.copyFromDestination(4, offset);
                },
                0b00 => {
                    // 100|oooo_oooo_o
                    // next 9 bits are relative offset: copy 3 bytes from uncompressed data at offset
                    const offset: usize = try reader.readInt(u9);
                    try writer.copyFromDestination(3, offset);
                },
            }
        },
        0b0 => {
            switch (try reader.readBit()) {
                0b1 => {
                    // 01|oooo_oooo
                    // next 8 bits are relative offset: copy 2 bytes from uncompressed data at offset
                    const offset: usize = try reader.readInt(u8);
                    try writer.copyFromDestination(2, offset);
                },
                0b0 => {
                    // 00|ccc
                    // next 3 bits are count: write the subsequent (count + 1) bytes of raw data
                    const count: usize = try reader.readInt(u3);
                    try writer.writeFromSource(reader, count + 1);
                },
            }
        },
    }
}

// -- Tests --

const testing = @import("../utils/testing.zig");
const mockReader = @import("test_helpers/mock_reader.zig").mockReader;
const MockWriter = @import("test_helpers/mock_writer.zig").MockWriter;

test "decodeNextInstruction parses 111 instruction" {
    // 111|cccc_cccc: 11 bits total
    // next 8 bits are count: copy the next (count + 9) bytes of packed data immediately after this.
    var reader = mockReader(u11, 0b111_0111_1101);
    var writer = MockWriter.init();

    try decodeInstruction(&reader, &writer);

    try testing.expectEqual(
        .{ .write_from_source = 0b0111_1101 + 9 },
        writer.last_instruction,
    );
    try testing.expect(reader.isAtEnd());
}

test "decodeNextInstruction parses 111 instruction with max count without overflowing" {
    var reader = mockReader(u11, 0b111_1111_1111);
    var writer = MockWriter.init();

    try decodeInstruction(&reader, &writer);

    try testing.expectEqual(
        .{ .write_from_source = 0b1111_1111 + 9 },
        writer.last_instruction,
    );
    try testing.expect(reader.isAtEnd());
}

test "decodeNextInstruction parses 110 instruction" {
    // 110|cccc_cccc|oooo_oooo_oooo: 23 bits total
    // next 8 bits are count, next 12 bits are relative offset within uncompressed data:
    // copy (count + 1) bytes from the uncompressed data at that offset.
    var reader = mockReader(u23, 0b110_0111_1101_1101_1001_1010);
    var writer = MockWriter.init();

    try decodeInstruction(&reader, &writer);

    try testing.expectEqual(
        .{
            .copy_from_destination = .{
                .count = 0b0111_1101 + 1,
                .offset = 0b1101_1001_1010,
            },
        },
        writer.last_instruction,
    );
    try testing.expect(reader.isAtEnd());
}

test "decodeNextInstruction parses 101 instruction" {
    // 101|oooo_oooo_oo: 13 bits total
    // next 10 bits are relative offset: copy 4 bytes from uncompressed data at offset.
    var reader = mockReader(u13, 0b101_0111_1101_11);
    var writer = MockWriter.init();

    try decodeInstruction(&reader, &writer);

    try testing.expectEqual(
        .{
            .copy_from_destination = .{
                .count = 4,
                .offset = 0b0111_1101_11,
            },
        },
        writer.last_instruction,
    );
    try testing.expect(reader.isAtEnd());
}

test "decodeNextInstruction parses 100 instruction" {
    // 100|oooo_oooo_o: 12 bits total
    // next 9 bits are relative offset: copy 3 bytes from uncompressed data at offset.
    var reader = mockReader(u12, 0b100_0111_1101_1);
    var writer = MockWriter.init();

    try decodeInstruction(&reader, &writer);

    try testing.expectEqual(
        .{
            .copy_from_destination = .{
                .count = 3,
                .offset = 0b0111_1101_1,
            },
        },
        writer.last_instruction,
    );
    try testing.expect(reader.isAtEnd());
}

test "decodeNextInstruction parses 01 instruction" {
    // 01|oooo_oooo: 10 bits total
    // next 8 bits are relative offset: copy 2 bytes from uncompressed data at offset.
    var reader = mockReader(u10, 0b01_0111_1101);
    var writer = MockWriter.init();

    try decodeInstruction(&reader, &writer);

    try testing.expectEqual(
        .{
            .copy_from_destination = .{
                .count = 2,
                .offset = 0b0111_1101,
            },
        },
        writer.last_instruction,
    );
    try testing.expect(reader.isAtEnd());
}

test "decodeNextInstruction parses 00 instruction" {
    // 00|ccc: 5 bits total
    // next 3 bits are count: copy the next (count + 1) bytes immediately after the instruction.
    var reader = mockReader(u5, 0b00_110);
    var writer = MockWriter.init();

    try decodeInstruction(&reader, &writer);

    try testing.expectEqual(
        .{ .write_from_source = 0b110 + 1 },
        writer.last_instruction,
    );
    try testing.expect(reader.isAtEnd());
}
