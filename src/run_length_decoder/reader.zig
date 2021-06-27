const std = @import("std");
const mem = std.mem;

const ReaderMethods = @import("reader_methods.zig");

/// Returns a new reader that consumes the specified source buffer.
/// This reads chunks of 4 bytes starting from the end of the buffer and returns their individual bits,
/// to be interpreted by the decoder as RLE instructions or raw data.
pub fn new(source: []const u8) !Instance {
    return try Instance.init(source);
}

const Instance = struct {
    /// The source buffer to read from.
    source: []const u8,

    /// The current position of the reader within `source`.
    /// The reader works backward from the end of the source buffer, 4 bytes at a time.
    cursor: usize,

    /// The expected uncompressed size of the compressed data, read from the last byte of the data.
    /// Only used as a sanity check, and is not used during parsing.
    uncompressed_size: usize,

    /// The current chunk that `readBit` is currently pulling bits from.
    /// Once this chunk is exhausted, `readBit` will load the next one.
    current_chunk: u32,

    /// The current CRC. This is updated as each subsequent chunk is read;
    /// once all bits have been read from the source data, this should be 0.
    /// While decoding is in progress, the CRC should be ignored.
    crc: u32,

    /// Create and initialize a reader to consume the specified source data.
    /// Returns an error if the source buffer does not contain enough bytes to initialize the reader.
    fn init(source: []const u8) Error!Instance {
        var self: Instance = undefined;

        self.source = source;
        self.cursor = source.len;
        self.uncompressed_size = try self.popChunk();
        self.crc = try self.popChunk();

        // HERE BE DRAGONS
        //
        // currentChunk always has an extra 1 bit after its most significant bit, to mark how many bits are left
        // to consume from that chunk. Once the chunk is down to a single 1, it means we've consumed all of
        // the significant bits before that marker and it's time to load the next chunk.
        //
        // Normally when `readBit` loads in the next chunk and pops off the first bit, it then sets the top bit to 1
        // to mark that we have 31 more bits to go in that chunk. That step does *not* happen for the first chunk
        // when we load it here in `init`: Instead, the first chunk should *already* have the most significant bit
        // marker encoded into it in the original game data. This is because compressed game resources usually won't
        // fall on nice tidy 4-byte boundaries, and the first chunk will be a partial chunk containing the remainder.

        // This also means that the first chunk can have a maximum of 31 significant bits; at least one bit is "lost"
        // to the hardcoded marker. In the event that all the real data did fall on a 4-byte boundary, we would expect
        // the first chunk to consist of all zeroes, or 31 zeroes and a 1 at the end. Such a chunk would be skipped
        // altogether by `readBit`.
        self.current_chunk = try self.popChunk();
        self.crc ^= self.current_chunk;

        return self;
    }

    /// Consume the next bit from the source data, automatically advancing to the next chunk of source data if necessary.
    /// Returns error.SourceExhausted if there are no more chunks remaining.
    pub fn readBit(self: *Instance) Error!u1 {
        const next_bit = self.popBit();

        // Because we set the highest bit of the in-progress chunk to 1, if `current_chunk` is ever equal to 0
        // after we pop the lowest bit, it means we've read through all the meaningful bits in the chunk.
        // Once we exhaust the chunk, disregard the popped bit (which was therefore our "done" marker)
        // and load in the next chunk.
        if (self.current_chunk == 0) {
            self.current_chunk = try self.popChunk();
            self.crc ^= self.current_chunk;

            const real_next_bit = self.popBit();
            // Set the last bit of the chunk to be our marker that we have exhausted the chunk:
            // once that final bit is popped off, the chunk will be equal to 0.
            // (This way, we don't have to maintain a counter of how many bits we've read.)
            self.current_chunk |= 0b10000000_00000000_00000000_00000000;

            return real_next_bit;
        } else {
            return next_bit;
        }
    }

    /// Pop the rightmost bit from the current chunk.
    fn popBit(self: *Instance) u1 {
        const next_bit = @truncate(u1, self.current_chunk);
        self.current_chunk >>= 1;
        return next_bit;
    }

    /// Return the next 4 bytes from the end of the source data and move the cursor
    /// backwards to the preceding chunk.
    /// Returns `error.SourceExhausted` if there are no more chunks remaining.
    fn popChunk(self: *Instance) Error!u32 {
        comptime const chunk_size = 4;

        const old_cursor = self.cursor;
        if (old_cursor < chunk_size) {
            return error.SourceExhausted;
        }

        self.cursor -= chunk_size;
        return mem.readIntSliceBig(u32, self.source[self.cursor..old_cursor]);
    }

    /// Whether the reader still has bits remaining to consume.
    pub fn isAtEnd(self: Instance) bool {
        // The most significant bit of the current chunk is always 1;
        // once the chunk is down to a value of 1 or 0, all its bits have been fully consumed.
        return self.cursor == 0 and self.current_chunk <= 0b1;
    }

    /// Call once decoding is complete and the reader is expected to be fully consumed,
    /// to verify that the final checksum is valid.
    pub fn validateChecksum(self: Instance) Error!void {
        // It is an error to check the checksum before the reader has consumed all its chunks,
        // since the checksum will be in a partial state.
        if (self.isAtEnd() == false) {
            return error.ChecksumNotReady;
        }

        if (self.crc != 0) {
            return error.ChecksumFailed;
        }

        // If we got this far, the reader consumed all its bytes and had a valid checksum.
    }

    // Add methods for reading bytes and whole integers
    usingnamespace ReaderMethods.extend(Instance);
};

/// The possible errors from a reader instance.
pub const Error = error{
    /// The reader ran out of bits to consume before decoding was completed.
    SourceExhausted,

    /// Attempted to validate the checksum before reading had finished.
    ChecksumNotReady,

    /// The reader failed its checksum, likely indicating that the compressed data was corrupt or truncated.
    ChecksumFailed,
};

// -- Test helpers --

// zig fmt: off
const DataExamples = struct {
    const valid = [_]u8{
        // A couple of chunks of raw data that will be returned by readBit.
        0x8B, 0xAD, 0xF0, 0x0D,
        0xDE, 0xAD, 0xBE, 0xEF,
        // Empty chunk to ensure preceding chunks are consumed in full - see comment in Instance.init.
        // This chunk will contribute to the CRC but will not be returned by readBit.
        0x00, 0x00, 0x00, 0x01,
        // The starting checksum is XORed with each subsequent chunk as it is read;
        // the end result of XORing all chunks into the original checksum should be 0.
        (0x8B ^ 0xDE ^ 0x00), (0xAD ^ 0xAD ^ 0x00), (0xF0 ^ 0xBE ^ 0x00), (0x0D ^ 0xEF ^ 0x01),
        // Expected size of uncompressed data (unused in tests)
        0x8B, 0xAD, 0xF0, 0x0D,
    };

    const invalid_checksum = [_]u8{
        0x8B, 0xAD, 0xF0, 0x0D,
        0xDE, 0xAD, 0xBE, 0xEF,
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x00, // Invalid checksum for the preceding chunks
        0x8B, 0xAD, 0xF0, 0x0D,
    };
};
// zig fmt: on

// -- Tests --

const testing = @import("../utils/testing.zig");
const io = std.io;

test "init() reads unpacked size, initial checksum and first chunk from end of source buffer" {
    const source = DataExamples.valid;

    var reader = try Instance.init(&source);

    try testing.expectEqual(0x8BADF00D, reader.uncompressed_size);
    try testing.expectEqual(0x00000001, reader.current_chunk);

    // During initialization, the CRC stored in the source data gets XORed with the first raw chunk of data.
    const expected_crc = mem.readIntBig(u32, source[12..16]) ^ mem.readIntBig(u32, source[8..12]);
    try testing.expectEqual(expected_crc, reader.crc);
}

test "new() returns `error.SourceExhausted` when source buffer is too small" {
    const source = [_]u8{0};

    try testing.expectError(error.SourceExhausted, new(&source));
}

test "readBit() reads chunks bit by bit in reverse order" {
    const source = DataExamples.valid;
    var reader = try new(&source);

    var destination: [8]u8 = undefined;
    const destination_stream = io.fixedBufferStream(&destination).writer();
    var writer = io.bitWriter(.Big, destination_stream);

    var bits_remaining = destination.len * 8;
    while (bits_remaining > 0) : (bits_remaining -= 1) {
        const bit = try reader.readBit();
        try writer.writeBits(bit, 1);
    }
    try testing.expectEqual(true, reader.isAtEnd());

    // readBit() returns source bits in reverse order, starting from the end of the last chunk of real data.
    const source_bits = mem.readIntBig(u64, source[0..destination.len]);
    const expected_bits = @bitReverse(u64, source_bits);
    const actual_bits = mem.readIntBig(u64, &destination);

    try testing.expectEqual(expected_bits, actual_bits);
}

test "isAtEnd() returns false and validateChecksum() returns error.ChecksumNotReady when reader hasn't consumed all bits yet" {
    const single_chunk_source = DataExamples.valid[4..];

    var reader = try new(single_chunk_source);
    try testing.expectEqual(false, reader.isAtEnd());
    try testing.expectError(error.ChecksumNotReady, reader.validateChecksum());

    // Even once it has begun consuming its last chunk,
    // it should not report as done until all bits of the chunk have been read
    _ = try reader.readBit();
    try testing.expectEqual(false, reader.isAtEnd());
    try testing.expectError(error.ChecksumNotReady, reader.validateChecksum());
}

test "isAtEnd() returns true and validateChecksum() returns error.ChecksumFailed when reader has consumed all bits but has a non-0 checksum" {
    var reader = try new(&DataExamples.invalid_checksum);

    var bits_remaining: usize = 8 * 8;
    while (bits_remaining > 0) : (bits_remaining -= 1) {
        try testing.expectEqual(false, reader.isAtEnd());
        try testing.expectError(error.ChecksumNotReady, reader.validateChecksum());
        _ = try reader.readBit();
    } else {
        try testing.expectEqual(true, reader.isAtEnd());
        try testing.expectError(error.ChecksumFailed, reader.validateChecksum());
    }
}

test "isAtEnd() returns true and validateChecksum() passes when reader has consumed all bits and has a 0 checksum" {
    var reader = try new(&DataExamples.valid);

    var bits_remaining: usize = 8 * 8;
    while (bits_remaining > 0) : (bits_remaining -= 1) {
        try testing.expectEqual(false, reader.isAtEnd());
        try testing.expectError(error.ChecksumNotReady, reader.validateChecksum());
        _ = try reader.readBit();
    } else {
        try testing.expectEqual(true, reader.isAtEnd());
        try reader.validateChecksum();
    }
}
