const std = @import("std");
const mem = std.mem;
const io = std.io;

const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const trait = std.meta.trait;
const introspection = @import("../../utils/introspection.zig");

pub fn new(allocator: *mem.Allocator) Instance {
    return Instance.init(allocator);
}

/// Builds an RLE-encoded payload that can be decompressed by a call to decode.
/// Only intended to be used for creating test fixtures.
const Instance = struct {
    payload: ArrayList(u8),
    bits_written: usize,
    uncompressed_size: u32,

    /// Create a new empty encoder.
    /// Caller owns the returned encoder and must free it by calling `deinit`.
    fn init(allocator: *mem.Allocator) Instance {
        return .{
            .payload = ArrayList(u8).init(allocator),
            .bits_written = 0,
            .uncompressed_size = 0,
        };
    }

    /// Free the memory used by the encoder itself.
    /// Any data that was returned by `finalize` is not owned and must be freed separately.
    /// After calling this function, the encoder can no longer be used.
    pub fn deinit(self: *Instance) void {
        self.payload.deinit();
        self.* = undefined;
    }

    /// Add an instruction that writes a raw 4-byte sequence to the end of the destination.
    pub fn write4Bytes(self: *Instance, bytes: [4]u8) !void {
        const instruction: u5 = 0b00_011; // Read 4 bytes
        try self.writeBits(instruction);

        // Reverse the bytes, so that the RLE writer will write them
        // from last to first to the end of its destination buffer.
        // That way they'll come out in the original intended order.
        var bytes_remaining: usize = 4;
        while (bytes_remaining > 0) : (bytes_remaining -= 1) {
            try self.writeBits(bytes[bytes_remaining - 1]);
        }

        self.uncompressed_size += 4;
    }

    /// Encode an invalid instruction to write more bytes than exist in the payload.
    pub fn invalidWrite(self: *Instance) !void {
        const instruction: u5 = 0b00_011; // Read 4 bytes
        try self.writeBits(instruction);

        self.uncompressed_size += 4;
    }

    /// Add an instruction that copies the previous 4 bytes that were written to the destination.
    pub fn copyPrevious4Bytes(self: *Instance) !void {
        const instruction: u13 = 0b101_0000_0001_00;
        try self.writeBits(instruction);

        self.uncompressed_size += 4;
    }

    /// Add the specified bit to the end of the payload,
    /// starting from the most significant bit of the first byte.
    fn writeBit(self: *Instance, bit: u1) !void {
        const byte_index = self.bits_written / 8;
        const shift = @intCast(u3, 7 - (self.bits_written % 8));
        const mask = @as(u8, bit) << shift;

        if (byte_index == self.payload.items.len) {
            _ = try self.payload.append(mask);
        } else {
            self.payload.items[byte_index] |= mask;
        }

        self.bits_written += 1;
    }

    /// Add the specified bits to the end of the payload, starting from the most significant bit of the first byte.
    fn writeBits(self: *Instance, bits: anytype) !void {
        comptime const Integer = @TypeOf(bits);
        comptime assert(trait.isUnsignedInt(Integer));
        comptime const bit_count = introspection.bitCount(Integer);
        comptime const ShiftType = introspection.shiftType(Integer);

        var bits_remaining: usize = bit_count;
        while (bits_remaining > 0) : (bits_remaining -= 1) {
            const shift = @intCast(ShiftType, bits_remaining - 1);
            const bit = @truncate(u1, bits >> shift);
            try self.writeBit(bit);
        }
    }

    /// The expected compressed size of the data returned by `finalize`, in bytes.
    pub fn compressedSize(self: Instance) usize {
        // Filled payload chunks + final partial chunk +  32-bit CRC + 32-bit uncompressed byte count
        var chunk_count = (self.bits_written / 32) + 1 + 1 + 1;
        return chunk_count * 4;
    }

    /// Convert the encoded instructions into valid compressed data with the proper CRC and uncompressed size chunks.
    /// Caller owns the returned slice and must deallocate it using `allocator`.
    pub fn finalize(self: *Instance, allocator: *mem.Allocator) ![]u8 {
        var output = ArrayList(u8).init(allocator);
        errdefer output.deinit();

        try output.ensureCapacity(self.compressedSize());

        var writer = output.writer();

        // Sentinel bit: this marks the end of the significant bits in the chunk.
        // For full chunks this will eventually get shifted off, but it will
        // remain in the final chunk (which is always partially filled)
        // to let the decoder know how many significant bits to read from it.
        var current_chunk: u32 = 0b1;
        var crc: u32 = 0;

        var bits_remaining: usize = self.bits_written;
        while (bits_remaining > 0) : (bits_remaining -= 1) {
            const index = bits_remaining - 1;
            const byte_index = index / 8;
            const shift = @intCast(u3, 7 - (index % 8));
            const bit = @truncate(u1, self.payload.items[byte_index] >> shift);

            // If the sentinel bit is in the topmost place, it means the bit we're adding is the last one
            // that will fit in this chunk: after this, push the chunk and start with a new one.
            const chunk_full = (current_chunk >> 31 == 0b1);

            current_chunk <<= 1;
            current_chunk |= bit;

            if (chunk_full) {
                try writer.writeIntBig(u32, current_chunk);
                crc ^= current_chunk;
                current_chunk = 0b1;
            }
        }

        // Push whatever's left of the current chunk as the final chunk.
        // This will include a sentinel bit as the highest significant bit,
        // to let the decoder know how many bits to pop off.
        //
        // If encoding had finished exactly on a chunk boundary,
        // this sentinel will be the lowest significant bit of the final chunk,
        // which will cause the rest of the (empty) chunk to be skipped.
        try writer.writeIntBig(u32, current_chunk);
        crc ^= current_chunk;

        // Write the final CRC and the uncompressed size.
        try writer.writeIntBig(u32, crc);
        try writer.writeIntBig(u32, self.uncompressed_size);

        return output.toOwnedSlice();
    }
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const decode = @import("../decode.zig").decode;

test "write4Bytes generates expected payload" {
    var encoder = Instance.init(testing.allocator);
    defer encoder.deinit();

    try encoder.write4Bytes(.{ 0xDE, 0xAD, 0xBE, 0xEF });
    try testing.expectEqual(5 + 32, encoder.bits_written);
    try testing.expectEqual(4, encoder.uncompressed_size);

    var stream = io.fixedBufferStream(encoder.payload.items);
    var reader = io.bitReader(.Big, stream.reader());

    try testing.expectEqual(0b00_011, reader.readBitsNoEof(u5, 5));
    // Raw bytes should be in reverse order so that they decode into their original order
    try testing.expectEqual(0xEFBEADDE, reader.readBitsNoEof(u32, 32));
}

test "copyPrevious4Bytes generates expected payload" {
    var encoder = Instance.init(testing.allocator);
    defer encoder.deinit();

    try encoder.copyPrevious4Bytes();
    try testing.expectEqual(13, encoder.bits_written);
    try testing.expectEqual(4, encoder.uncompressed_size);

    var stream = io.fixedBufferStream(encoder.payload.items);
    var reader = io.bitReader(.Big, stream.reader());

    try testing.expectEqual(0b101_0000_0001_00, reader.readBitsNoEof(u13, 13));
}

test "finalize produces valid decodable data" {
    var encoder = Instance.init(testing.allocator);
    defer encoder.deinit();

    try encoder.write4Bytes(.{ 0xDE, 0xAD, 0xBE, 0xEF });
    try encoder.copyPrevious4Bytes();

    try encoder.write4Bytes(.{ 0x8B, 0xAD, 0xF0, 0x0D });
    try encoder.copyPrevious4Bytes();

    try testing.expectEqual(16, encoder.uncompressed_size);
    try testing.expectEqual(24, encoder.compressedSize());

    var compressed_data = try encoder.finalize(testing.allocator);
    defer testing.allocator.free(compressed_data);

    try testing.expectEqual(encoder.compressedSize(), compressed_data.len);

    var destination = try testing.allocator.alloc(u8, encoder.uncompressed_size);
    defer testing.allocator.free(destination);

    try decode(compressed_data, destination);
    var destination_reader = io.fixedBufferStream(destination).reader();

    try testing.expectEqual(0x8BADF00D, destination_reader.readIntBig(u32));
    try testing.expectEqual(0x8BADF00D, destination_reader.readIntBig(u32));

    try testing.expectEqual(0xDEADBEEF, destination_reader.readIntBig(u32));
    try testing.expectEqual(0xDEADBEEF, destination_reader.readIntBig(u32));
}
