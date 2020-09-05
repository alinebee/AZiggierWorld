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
//!      but serves as a sanity check.)
//!    - the initial CRC checksum for the packed data.
//! 3. The decoder walks backwards through the rest of the packed data in 32-bit chunks: reading a run of bits,
//!    deciding how to unpack them, and writing the unpacked bytes into the destination buffer, starting at the end
//!    of the buffer and filling back to the start.
//!    (When extracting into the same buffer in place, this means the write cursor "chases" the read cursor, never overtaking it.)
//! 4. As the decoder reads each new 32-bit chunk of compressed data, it XORs it into the checksum.
//!    Once it has read all the expected bytes:
//!    - The read cursor and write cursors should both be at the start of the buffer.
//!    - The checksum should be equal to 0.

const Reader = @import("run_length_decoder/reader.zig");
const Writer = @import("run_length_decoder/writer.zig");
const Parser = @import("run_length_decoder/parser.zig");

const Error = Reader.Error || Writer.Error || error {
    /// The buffer allocated for uncompressed data was a different size
    /// than the compressed data claimed to need.
    UncompressedSizeMismatch,
    /// The writer filled up its destination buffer before the reader had finished.
    FinishedEarly,
    /// The reader failed its checksum, likely indicating that the compressed data was corrupt or truncated.
    ChecksumFailed,
};

/// Decodes Run-Length-Encoded data, reading RLE-compressed data from the source
/// and writing decompressed data to the destination.
/// `source` and `destination` are allowed to be the same buffer; if they are,
/// `source` should be located at the start of `destination` to prevent the writer
/// from overtaking the reader.
/// On success, `destination` contains fully uncompressed data.
/// Returns an error if decoding failed.
pub fn decode(source: []const u8, destination: []u8) Error!void {
    var parser = Parser.new(try Reader.new(source));

    if (parser.reader.uncompressed_size != destination.len) {
        return error.UncompressedSizeMismatch;
    }

    var writer = Writer.new(destination);

    while (writer.isAtEnd() == false) {
        switch(try parser.readInstruction()) {
            .write_from_compressed => |count| {
                try writer.writeFromSource(@TypeOf(parser), &parser, count);
            },
            .copy_from_uncompressed => |params| {
                try writer.copyFromDestination(params.count, params.offset);
            }
        }
    } else {
        switch (parser.reader.status()) {
            .data_remaining => return error.FinishedEarly,
            .finished_with_invalid_checksum => return error.ChecksumFailed,
            .finished_with_valid_checksum => return,
        }
    }
}
