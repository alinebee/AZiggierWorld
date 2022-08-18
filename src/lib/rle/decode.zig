//! Decodes data that was encoded using Another World's run-length-encoding compression.
//! Based on the reverse-engineered C++ implementation in https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter.
//!
//! The algorithm takes a source buffer of packed data and a destination buffer to extract the data into,
//! which can be one and the same: the compression algorithm is designed to be unpacked in a single buffer in place.
//!
//! The original implementation worked as follows:
//! 1. A buffer is allocated that's large enough to hold the expected *unpacked* size of the data.
//! 2. The *packed* data was read into that buffer.
//! 1. Starting at the end of the packed data, the unpacker reads 2 32-bit integers:
//!    - the unpacked size of the data. (Unused, since the expected size was already known,
//!      but serves as a correctness check.)
//!    - the initial CRC checksum for the packed data.
//! 3. The decoder walks backwards through the rest of the packed data in 32-bit chunks: reading a run of bits,
//!    deciding how to unpack them, and writing the unpacked bytes into the destination buffer, starting at the end
//!    of the buffer and filling back to the start.
//!    (When extracting into the same buffer in place, this means the write cursor "chases" the read cursor, never overtaking it.)
//! 4. As the decoder reads each new 32-bit chunk of compressed data, it XORs it into the checksum.
//!    Once it has read all the expected bytes:
//!    - The read cursor and write cursors should both be at the start of the buffer.
//!    - The checksum should be equal to 0.

const anotherworld = @import("../anotherworld.zig");

const Reader = @import("reader.zig").Reader;
const Writer = @import("writer.zig").Writer;
const decodeInstruction = @import("decode_instruction.zig").decodeInstruction;

const Error = Reader.Error || Writer.Error || error{
    /// The buffer allocated for uncompressed data was a different size
    /// than the compressed data claimed to need.
    UncompressedSizeMismatch,
};

/// Decodes Run-Length-Encoded data, reading RLE-compressed data from the source
/// and writing decompressed data to the destination.
///
/// On success, `destination` will contain the fully uncompressed data.
/// Returns an error if decoding failed.
///
/// Preconditions:
/// - The destination must be exactly large enough to hold the uncompressed data.
/// - `source` and `destination` are allowed to be the same region of memory;
///   if they are, `source` must be located at the start of `destination`
///   to prevent the writer from overtaking the reader.
pub fn decode(source: []const u8, destination: []u8) Error!void {
    var reader = try Reader.init(source);

    if (reader.uncompressed_size != destination.len) {
        return error.UncompressedSizeMismatch;
    }

    var writer = Writer.init(destination);

    while (reader.isAtEnd() == false and writer.isAtEnd() == false) {
        try decodeInstruction(&reader, &writer);
    }

    try reader.validateChecksum();
}

// -- Tests --

const testing = @import("utils").testing;
const MockEncoder = @import("test_helpers/mock_encoder.zig").MockEncoder;

test "decode decodes valid payload" {
    var encoder = MockEncoder.init(testing.allocator);
    defer encoder.deinit();

    const payload = [_]u8{ 0x8B, 0xAD, 0xF0, 0x0D };
    try encoder.write4Bytes(payload);

    const source = try encoder.finalize(testing.allocator);
    defer testing.allocator.free(source);

    const destination = try testing.allocator.alloc(u8, encoder.uncompressed_size);
    defer testing.allocator.free(destination);

    try decode(source, destination);

    try testing.expectEqualSlices(u8, &payload, destination);
}

test "decode returns error.UncompressedSizeMismatch when passed a destination that doesn't match the reported uncompressed size" {
    var encoder = MockEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.copyPrevious4Bytes();

    const source = try encoder.finalize(testing.allocator);
    defer testing.allocator.free(source);

    const destination = try testing.allocator.alloc(u8, encoder.uncompressed_size + 10);
    defer testing.allocator.free(destination);

    try testing.expectError(error.UncompressedSizeMismatch, decode(source, destination));
}

test "decode returns error.CopyOutOfRange on payload with invalid copy pointer" {
    var encoder = MockEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.copyPrevious4Bytes();

    const source = try encoder.finalize(testing.allocator);
    defer testing.allocator.free(source);

    const destination = try testing.allocator.alloc(u8, encoder.uncompressed_size);
    defer testing.allocator.free(destination);

    try testing.expectError(error.CopyOutOfRange, decode(source, destination));
}

test "decode returns error.SourceExhausted on payload with too few bytes" {
    var encoder = MockEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.invalidWrite();

    const source = try encoder.finalize(testing.allocator);
    defer testing.allocator.free(source);

    const destination = try testing.allocator.alloc(u8, encoder.uncompressed_size);
    defer testing.allocator.free(destination);

    try testing.expectError(error.SourceExhausted, decode(source, destination));
}

test "decode returns error.DestinationExhausted on payload with undercounted uncompressed size" {
    var encoder = MockEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.write4Bytes(.{ 0x8B, 0xAD, 0xF0, 0x0D });
    encoder.uncompressed_size -= 2;

    const source = try encoder.finalize(testing.allocator);
    defer testing.allocator.free(source);

    const destination = try testing.allocator.alloc(u8, encoder.uncompressed_size);
    defer testing.allocator.free(destination);

    try testing.expectError(error.DestinationExhausted, decode(source, destination));
}

test "decode returns error.InvalidChecksum on payload with corrupted byte" {
    var encoder = MockEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.write4Bytes(.{ 0x8B, 0xAD, 0xF0, 0x0D });

    const source = try encoder.finalize(testing.allocator);
    defer testing.allocator.free(source);

    try testing.expect(source[0] != 0xFF);
    source[0] = 0xFF;

    const destination = try testing.allocator.alloc(u8, encoder.uncompressed_size);
    defer testing.allocator.free(destination);

    try testing.expectError(error.ChecksumFailed, decode(source, destination));
}
