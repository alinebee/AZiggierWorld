//! This file defines a parser that extracts image pixels from Another World's bitmap resource data.
//!
//! Another World's bitmap resources encoded a 320x200 16-color image in a bitplane format,
//! where the 4 bits that made up a single destination pixel were split across
//! 4 separate regions (planes) of the source bitmap, one plane after the other.
//!
//! Since Another World was programmed on an Amiga 500, this may have been done
//! to match the planar layout of the Amiga 500's framebuffer, documented here:
//! http://fabiensanglard.net/another_world_polygons_amiga500/index.html
//!
//! (Speculation: the Amiga architecture may have used bitplanes to support its 32-color (5-bit)
//! and 64-color (6-bit) palettes. A 16-color (4-bit) indexed image can be stored cleanly into
//! a byte buffer by packing 2 color indexes into each byte; but 5- or 6- bit color indexes
//! would either waste a lot of space in order to stay byte-aligned, or else be spread across
//! byte boundaries and need to be masked in awkward ways. Planes allow arbitrary index sizes
//! to be stored efficiently.)

const ColorID = @import("../values/color_id.zig");

const math = @import("std").math;
const debug = @import("std").debug;

/// Given a pair of image dimensions and a pointer to planar bitmap data, returns a reader
/// that parses each pixel of an image with those dimensions, from top left to bottom right.
/// Returns error.InvalidBitmapSize if the data is the wrong byte length for the dimensions.
pub fn new(comptime width: usize, comptime height: usize, data: []const u8) Error!Reader(width, height) {
    return Reader(width, height).init(data);
}

/// Returns a reader suitable for reading a planar bitmap resource of the specified pixel width and height.
pub fn Reader(comptime width: usize, comptime height: usize) type {
    const plane_count = 4;

    const stride = try math.divCeil(usize, width, 2);
    const bytes_required = height * stride;
    // Buffers must contain at least 4 bytes for the algorithm to work.
    comptime debug.assert(bytes_required >= plane_count);

    const plane_length = @divExact(bytes_required, plane_count);

    const Plane = [plane_length]u8;
    const Planes = *const [plane_count]Plane;

    comptime debug.assert(@sizeOf(@typeInfo(Planes).Pointer.child) == bytes_required);

    return struct {
        /// The source bitmap data divided into 4 sequential planes.
        planes: Planes,
        /// The current chunk of 4 bytes (one from each plane) that the reader is reading bits from.
        current_chunk: [plane_count]u8 = undefined,
        /// The index of the current chunk within each plane, between 0 and [length of plane].
        chunk_index: usize = 0,
        /// The number of bits remaining to read from each byte in the current chunk. Between 0 and 8.
        bits_remaining: usize = 0,

        const Self = @This();

        /// Create a new reader from a pointer to raw bitmap data.
        /// Returns error.InvalidBitmapSize if the pointer is
        /// the wrong length to contain the expected pixel data.
        pub fn init(raw_data: []const u8) Error!Self {
            if (raw_data.len != bytes_required) {
                return error.InvalidBitmapSize;
            }

            return Self{ .planes = @ptrCast(Planes, raw_data) };
        }

        /// Read the next pixel from the source data.
        /// Returns error.EndOfStream if all pixels have been read.
        pub fn readColor(self: *Self) Error!ColorID.Trusted {
            if (self.bits_remaining == 0) try self.loadNextChunk();

            var color: ColorID.Trusted = 0;

            // Pop the highest bit from each of the 4 planar bytes and push them onto the color.
            for (self.current_chunk) |*byte| {
                const bit = @truncate(u1, byte.* >> 7);

                color <<= 1;
                color |= bit;

                byte.* <<= 1;
            }

            self.bits_remaining -= 1;

            return color;
        }

        /// Whether the reader has read all pixels in the source bitmap data.
        pub fn isAtEnd(self: Self) bool {
            return self.chunk_index >= plane_length and self.bits_remaining == 0;
        }

        /// Called every 4 bytes to load the next chunk once the current one is exhausted.
        /// Returns error.EndOfStream if all chunks in the source data have been read.
        fn loadNextChunk(self: *Self) !void {
            const index = self.chunk_index;

            if (index >= plane_length) {
                return error.EndOfStream;
            }

            // Load the source bitmap 4 bytes at a time, reading a byte from each plane.
            // The planes were stored in reverse order, for some unknown reason:
            // The bits in each of the resulting pixels will be in the order { 3, 2, 1, 0 }.
            self.current_chunk = .{
                self.planes[3][index],
                self.planes[2][index],
                self.planes[1][index],
                self.planes[0][index],
            };

            self.chunk_index += 1;
            self.bits_remaining = @bitSizeOf(u8);
        }
    };
}

/// The possible errors that can occur when reading planar bitmap data from a resource.
pub const Error = error{
    InvalidBitmapSize,
    EndOfStream,
};

// -- Examples --

pub const DataExamples = struct {
    // zig fmt: off
    /// A planar image containing 16 pixels @ 2 pixels per byte, 2 bytes per plane, 4 planes.
    pub const valid_16px = [_]u8 {
        // Read from bottom to top, left to right to get the final pixel values.
        //01234567    89ABCDEF
        0b11111111, 0b00000000, // Plane 0
        0b00000000, 0b11111111, // Plane 1
        0b00001111, 0b11110000, // Plane 2
        0b01010101, 0b10101010, // Plane 3
    };
    // zig fmt: on
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const print = @import("std").debug.print;

test "Parses planar data properly" {
    const data = &DataExamples.valid_16px;
    var reader = try new(4, 4, data);
    try testing.expectEqual(false, reader.isAtEnd());

    const expected = [16]ColorID.Trusted{
        0b0001, // 0
        0b1001, // 1
        0b0001, // 2
        0b1001, // 3

        0b0101, // 4
        0b1101, // 5
        0b0101, // 6
        0b1101, // 7

        0b1110, // 8
        0b0110, // 9
        0b1110, // A
        0b0110, // B

        0b1010, // C
        0b0010, // D
        0b1010, // E
        0b0010, // F
    };

    var actual: [16]ColorID.Trusted = undefined;
    for (actual) |*color| {
        color.* = try reader.readColor();
    }

    try testing.expectEqual(true, reader.isAtEnd());
    try testing.expectEqualSlices(ColorID.Trusted, &expected, &actual);
}

test "new returns error.InvalidBitmapSize if source data is the wrong length for requested dimensions" {
    const data = &DataExamples.valid_16px;

    try testing.expectError(error.InvalidBitmapSize, new(4, 2, data));
    try testing.expectError(error.InvalidBitmapSize, new(320, 200, data));
}

test "readColor returns error.EndOfStream once reader is exhausted" {
    const data = &DataExamples.valid_16px;
    var reader = try new(4, 4, data);
    try testing.expectEqual(false, reader.isAtEnd());

    while (reader.isAtEnd() == false) {
        _ = try reader.readColor();
    }

    try testing.expectError(error.EndOfStream, reader.readColor());
}
