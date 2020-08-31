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

const Error = Reader.Error;