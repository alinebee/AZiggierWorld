const std = @import("std");

pub const Error = error {
    /// The read buffer ran out of bytes to read before decoding was completed.
    ReadBufferEmpty,
};

/// The completion status of the reader.
pub const Status = enum {
    /// The reader still has data left to parse.
    data_remaining,
    /// The reader has read all data and its checksum is valid.
    finished_with_valid_checksum,
    /// The reader has read all data and its checksum is invalid.
    finished_with_invalid_checksum,
};

/// The bitwise reader for the run-length decoder.
/// This reads chunks of 4 bytes starting from the end of the packed data and returns their individual bits,
/// to be interpreted by the decoder as RLE instructions or data.
pub const Instance = struct {
    /// The source buffer to read from.
    source: []const u8,

    /// The current position of the reader within `source`.
    /// The reader works backward from the end of the source buffer, 4 bytes at a time.
    cursor: usize,

    /// The expected decoded size of the compressed data, read from the last byte of the data.
    /// Only used as a sanity check, and is not used during parsing.
    decoded_size: usize,

    /// The current chunk that `readBit` is currently pulling bits from.
    /// Once this chunk is exhausted, `readBit` will load the next one.
    current_chunk: u32,

    /// The current CRC. This is updated as each subsequent chunk is read;
    /// once all chunks have been read from the source data, this should be 0.
    crc: u32,

    /// Prepares the reader to consume the specified source data.
    fn init(self: *Instance, source: []const u8) !void {
        self.source = source;
        self.cursor = source.len;
        self.decoded_size = try self.popChunk();
        self.crc = try self.popChunk();
        
        // CHECKME: the reference implementation loads the next 4 bytes as the current chunk, as per the code below.
        // This possibly contains a bug: it does not set the high bit on the loaded chunk the way `readBit` does,
        // which would cause it to stop parsing the chunk early if there are any leading zeroes.
        // That *ought* to corrupt all subsequent output, and result in the decode operation failing to read 
        // all the bits; but the reference implementation worked fine, so that suggests that this is by design.
        // The encoding algorithm may store the last chunk as a partial chunk with the high bit sentinel "further in"
        // to the chunk than bit 31, to allow for resources that don't fall on 4-byte boundaries.
        //
        // We can verify this once we get as far as parsing game resource files properly.
        // self.current_chunk = try self.readNextChunk();
        // self.crc ^= self.current_chunk;

        // This ensures that the first time `readBit` is called, it will load the next chunk.
        self.current_chunk = 0;
    }

    /// Consume the next bit from the source data, automatically advancing to the next chunk of source data if necessary.
    /// Returns error.ReadBufferEmpty if there are no more chunks remaining.
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
    /// Returns `error.ReadBufferEmpty` if there are no more chunks remaining.
    fn popChunk(self: *Instance) Error!u32 {
        comptime const chunk_size = @divExact(u32.bit_count, 8);

        const old_cursor = self.cursor;
        if (old_cursor < chunk_size) {
            return error.ReadBufferEmpty;
        }

        self.cursor -= chunk_size;
        return std.mem.readIntSliceBig(u32, self.source[self.cursor..old_cursor]);
    }

    fn status(self: Instance) Status {
        // The most significant bit of the current chunk is always 1;
        // once the chunk is down to a value of 1 or 0, all its bits have been fully consumed.
        if (self.cursor == 0 and self.current_chunk <= 0b1) {
            if (self.crc == 0) {
                return .finished_with_valid_checksum;
            } else {
                return .finished_with_invalid_checksum;
            }
        } else {
            return .data_remaining;
        }
    }
};

/// Construct a new reader that consumes the specified source slice.
pub fn new(source: []const u8) !Instance {
    var reader: Instance = undefined;
    try reader.init(source);
    return reader;
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "new() reads unpacked size and initial checksum from end of source buffer" {
    const source = [_]u8 {
        // Second-to-last 4 bytes are checksum
        0xDE, 0xAD, 0xBE, 0xEF,

        // Last 4 bytes are decoded size
        0x0B, 0xAD, 0xF0, 0x0D,
    };

    const reader = try new(&source);

    testing.expectEqual(0x0BADF00D, reader.decoded_size);
    testing.expectEqual(0xDEADBEEF, reader.crc);
    testing.expectEqual(0, reader.cursor);
}

test "new() returns `error.ReadBufferEmpty` when source buffer is too small" {
    const source = [_]u8 { 0 };

    testing.expectError(error.ReadBufferEmpty, new(&source));
}

test "readBit() reads next bit and advances to next chunk" {
    const pattern: u8 = 0b0101_000;

    const source = ([_]u8 { pattern } ** 8) ++ ([_]u8 {
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

test "status() returns .data_remaining for reader that hasn't exhausted its chunks" {
    const source = [_]u8 {
        0x00, 0x00, 0x00, 0x00,
        0xDE, 0xAD, 0xBE, 0xEF,
        0x0B, 0xAD, 0xF0, 0x0D,
    };

    var reader = try new(&source);
    testing.expectEqual(4, reader.cursor);
    testing.expectEqual(.data_remaining, reader.status());
    
    // Even once it has begun consuming its last chunk,
    // it should not report as done until all bits of the chunk have been read
    _ = try reader.readBit();
    testing.expectEqual(0, reader.cursor);
    testing.expectEqual(.data_remaining, reader.status());
}

test "status() returns .finished_with_valid_checksum for exhausted reader whose checksum is 0" {
    const source = [_]u8 {
        0x0B, 0xAD, 0xF0, 0x0D,
        0xDE, 0xAD, 0xBE, 0xEF,
        // The starting checksum is XORed with each subsequent chunk as it is read;
        // the end result of XORing all chunks into the original checksum should be 0.
        (0x0B ^ 0xDE), (0xAD ^ 0xAD), (0xF0 ^ 0xBE), (0x0D ^ 0xEF),
        0x0B, 0xAD, 0xF0, 0x0D,
    };

    var reader = try new(&source);

    var bits_remaining: usize = 8 * 8;
    while (bits_remaining > 0) : (bits_remaining -= 1) {
        testing.expectEqual(.data_remaining, reader.status());
        _ = try reader.readBit();
    } else {
        testing.expectEqual(0, reader.cursor);
        testing.expectEqual(0, reader.crc);
        testing.expectEqual(.finished_with_valid_checksum, reader.status());
    }
}

test "status() returns .finished_with_invalid_checksum for exhausted reader whose checksum is non-0" {
    const source = [_]u8 {
        0x0B, 0xAD, 0xF0, 0x0D,
        0xDE, 0xAD, 0xBE, 0xEF,
        0x00, 0x00, 0x00, 0x00, // Invalid checksum for the preceding chunks
        0x0B, 0xAD, 0xF0, 0x0D,
    };

    var reader = try new(&source);

    var bits_remaining: usize = 8 * 8;
    while (bits_remaining > 0) : (bits_remaining -= 1) {
        testing.expectEqual(.data_remaining, reader.status());
        _ = try reader.readBit();
    } else {
        testing.expectEqual(0, reader.cursor);
        testing.expectEqual(.finished_with_invalid_checksum, reader.status());
    }
}