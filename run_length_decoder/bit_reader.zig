const std = @import("std");

/// Construct a new reader that consumes the specified source slice.
pub fn new(source: []const u8) !Instance {
    var reader: Instance = undefined;
    try reader.init(source);
    return reader;
}

/// The bitwise reader for the run-length decoder.
/// This reads chunks of 4 bytes starting from the end of the packed data and returns their individual bits,
/// to be interpreted by the decoder as RLE instructions or data.
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

    /// Prepares the reader to consume the specified source data.
    fn init(self: *Instance, source: []const u8) Error!void {
        self.source = source;
        self.cursor = source.len;
        self.uncompressed_size = try self.popChunk();
        self.crc = try self.popChunk();
        
        // HERE BE DRAGONS
        //
        // currentChunk always has an extra 1 after its most significant bit, to mark how many bits are left to consume
        // from that chunk. Once the chunk is down to a single 1,it means we've consumed all of the significant bits
        // before that marker and it's time to load the next chunk.
        //
        // Normally when `readBit` loads in the next chunk, it sets its top bit to 1 to mark that we have 31 more bits
        // to go in that chunk. But that step does *not* happen for the first chunk when we load it here in `init`:
        // Instead, the first chunk *already* has the most significant bit 1 encoded into it in the original game data.
        // This is because compressed game resources usually won't fall on nice tidy 4-byte boundaries, and the first
        // chunk will be a partial chunk containing the remainder.
        
        // (This also means that the first chunk can have a maximum of 31 significant bits; at least one bit is "lost"
        // to the hardcoded marker. In the event that all the real data did fall on a 4-byte boundary, we would expect
        // the first chunk to consist of all zeroes, or 31 zeroes and a 1 at the end. Such a chunk would be skipped
        // altogether by `readBit`.
        self.current_chunk = try self.popChunk();
        self.crc ^= self.current_chunk;
    }

    /// Consume the next bit from the source data, automatically advancing to the next chunk of source data if necessary.
    /// Returns error.SourceBufferEmpty if there are no more chunks remaining.
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
    /// Returns `error.SourceBufferEmpty` if there are no more chunks remaining.
    fn popChunk(self: *Instance) Error!u32 {
        comptime const chunk_size = @divExact(u32.bit_count, 8);

        const old_cursor = self.cursor;
        if (old_cursor < chunk_size) {
            return error.SourceBufferEmpty;
        }

        self.cursor -= chunk_size;
        return std.mem.readIntSliceBig(u32, self.source[self.cursor..old_cursor]);
    }

    /// Whether the reader still has bits remaining to consume.
    pub fn isAtEnd(self: Instance) bool {
        // The most significant bit of the current chunk is always 1;
        // once the chunk is down to a value of 1 or 0, all its bits have been fully consumed.
        return self.cursor == 0 and self.current_chunk <= 0b1;
    }

    /// Call once decoding is complete and the reader is expected to be fully consumed,
    /// to verify that all bits *were* actually consumed and the final checksum is valid.
    pub fn validateAfterDecoding(self: Instance) Error!void {
        if (self.isAtEnd() == false) {
            return error.SourceBufferNotFullyConsumed;
        }

        if (self.crc != 0) {
            return error.ChecksumFailed;
        }

        // If we got this far, the reader consumed all its bytes and had a valid checksum.
    }
};

/// The possible errors from a reader instance.
pub const Error = error {
    /// The reader ran out of bits to consume before decoding was completed.
    SourceBufferEmpty,
    
    /// Decoding completed before the reader had fully consumed all bits.
    SourceBufferNotFullyConsumed,

    /// The reader failed its checksum, likely indicating that the compressed data was corrupt or truncated.
    ChecksumFailed,
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "new() reads unpacked size, initial checksum and first chunk from end of source buffer" {
    const source = [_]u8 {
        // Preceding bytes are compressed resource data
        0x00, 0x00, 0x00, 0x00,
        
        // Second-to-last 4 bytes are checksum
        0xDE, 0xAD, 0xBE, 0xEF,

        // Last 4 bytes are decoded size
        0x0B, 0xAD, 0xF0, 0x0D,
    };

    const reader = try new(&source);

    testing.expectEqual(0x0BADF00D, reader.uncompressed_size);
    testing.expectEqual(0xDEADBEEF, reader.crc);
    testing.expectEqual(0x00000000, reader.current_chunk);
}

test "new() returns `error.SourceBufferEmpty` when source buffer is too small" {
    const source = [_]u8 { 0 };

    testing.expectError(error.SourceBufferEmpty, new(&source));
}

test "readBit() reads next bit and advances to next chunk" {
    const pattern: u8 = 0b0101_000;

    const source = ([_]u8 { pattern } ** 8) ++ ([_]u8 {
        // Empty chunk to ensure preceding chunks are consumed in full - see comment in Instance.init.
        0x00, 0x00, 0x00, 0x01,
        0xDE, 0xAD, 0xBE, 0xEF,
        0x0B, 0xAD, 0xF0, 0x0D,
    });
    var reader = try new(&source);

    // HERE BE DRAGONS: to test the output of the reader, we push each bit
    // back into a BitWriter and compare the final slice it writes at the end.
    // The output of Reader is big-endian, so low bits come out first.
    // If we pushed those into a big-endian BitWriter, it would flip the order,
    // because the lowmost bits from the source would end up as the highmost
    // bits of the destination.
    // By creating a little-endian BitWriter, the lowmost bits we push in end up
    // as the lowmost bits of the destination too, allowing for an easier comparison.
    var destination: [8]u8 = undefined;
    const destination_stream = std.io.fixedBufferStream(&destination).writer();
    var writer = std.io.bitWriter(.Little, destination_stream);

    var bits_remaining = destination.len * 8;
    while (bits_remaining > 0) : (bits_remaining -= 1) {
        const bit = try reader.readBit();
        try writer.writeBits(bit, 1);
    }

    testing.expectEqual(0, reader.cursor);
    // Only a single sentinel bit should be left in the reader at this point,
    // since two chunks have been read fully.
    testing.expectEqual(0b1, reader.current_chunk);
    testing.expectEqualSlices(u8, source[0..destination.len], &destination);
}

test "isAtEnd() returns false and validateAfterDecoding() returns error.SourceBufferNotFullyConsumed when reader hasn't consumed all bits yet" {
    const source = [_]u8 {
        0x01, 0x01, 0x01, 0x01,
        0xDE, 0xAD, 0xBE, 0xEF,
        0x0B, 0xAD, 0xF0, 0x0D,
    };

    var reader = try new(&source);
    testing.expectEqual(false, reader.isAtEnd());
    testing.expectError(error.SourceBufferNotFullyConsumed, reader.validateAfterDecoding());
    
    // Even once it has begun consuming its last chunk,
    // it should not report as done until all bits of the chunk have been read
    _ = try reader.readBit();
    testing.expectEqual(0, reader.cursor);
    testing.expectEqual(false, reader.isAtEnd());
    testing.expectError(error.SourceBufferNotFullyConsumed, reader.validateAfterDecoding());
}

test "isAtEnd() returns true and validateAfterDecoding() returns error.ChecksumFailed when reader has consumed all bits but has a non-0 checksum" {
    const source = [_]u8 {
        0x0B, 0xAD, 0xF0, 0x0D,
        0xDE, 0xAD, 0xBE, 0xEF,
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x00, // Invalid checksum for the preceding chunks
        0x0B, 0xAD, 0xF0, 0x0D,
    };

    var reader = try new(&source);

    var bits_remaining: usize = 8 * 8;
    while (bits_remaining > 0) : (bits_remaining -= 1) {
        testing.expectEqual(false, reader.isAtEnd());
        testing.expectError(error.SourceBufferNotFullyConsumed, reader.validateAfterDecoding());
        _ = try reader.readBit();
    } else {
        testing.expectEqual(0, reader.cursor);
        testing.expectEqual(true, reader.isAtEnd());
        testing.expectError(error.ChecksumFailed, reader.validateAfterDecoding());
    }
}

test "isAtEnd() returns true and validateAfterDecoding() passes when reader has consumed all bits and has a 0 checksum" {
    const source = [_]u8 {
        0x0B, 0xAD, 0xF0, 0x0D,
        0xDE, 0xAD, 0xBE, 0xEF,
        // Empty chunk to ensure preceding chunks are consumed in full - see comment in Instance.init.
        0x00, 0x00, 0x00, 0x01,
        // The starting checksum is XORed with each subsequent chunk as it is read;
        // the end result of XORing all chunks into the original checksum should be 0.
        (0x0B ^ 0xDE ^ 0x00), (0xAD ^ 0xAD ^ 0x00), (0xF0 ^ 0xBE ^ 0x00), (0x0D ^ 0xEF ^ 0x01),
        0x0B, 0xAD, 0xF0, 0x0D,
    };

    var reader = try new(&source);

    var bits_remaining: usize = 8 * 8;
    while (bits_remaining > 0) : (bits_remaining -= 1) {
        testing.expectEqual(false, reader.isAtEnd());
        testing.expectError(error.SourceBufferNotFullyConsumed, reader.validateAfterDecoding());
        _ = try reader.readBit();
    } else {
        testing.expectEqual(0, reader.cursor);
        testing.expectEqual(0, reader.crc);
        testing.expectEqual(true, reader.isAtEnd());
        try reader.validateAfterDecoding();
    }
}