const ResourceType = @import("resource_type.zig");
const Filename = @import("filename.zig");

//! Another World compresses hundreds of game resources (audio, bitmaps, bytecode polygon data)
//! into a set of BANK01-BANK0D data files. To keep track of where each resource lives,
//! the game defines _resource descriptors_ in a file named MEMLIST.BIN.
//!
//! This defines the structure of these resource descriptors, along with methods
//! to parse them from a MEMLIST.BIN file.

/// Describes an individual resource in Another World's data files:
/// its length, type and the bank file in which it is located.
pub const Instance = struct {
    /// The type of content stored in this resource.
    type: ResourceType.Enum,
    /// The bank file to look for the resource in: in the MS-DOS version these are numbered from 01 to 0D.
    bank_id: Filename.BankID,
    /// The byte offset (within the packed data of the bank file) at which the resource is located.
    bank_offset: usize,
    /// The compressed size of the resource in bytes.
    compressed_size: usize,
    /// The uncompressed size of the resource in bytes.
    /// If this differs from compressed_size, it indicates the resource has been compressed
    /// with run-length encoding (RLE).
    uncompressed_size: usize,

    pub fn isCompressed(self: Instance) bool {
        return self.uncompressed_size != self.compressed_size;
    }
};

pub fn Error(comptime Reader: type) type {
    comptime const ReaderError = @TypeOf(Reader.readNoEof).ReturnType.ErrorSet;

    return ReaderError || ResourceType.Error || error {
        /// A resource defined a compressed size that was larger than its uncompressed size. 
        InvalidResourceSize,
    };
}

/// An iterator that parses resource descriptors from a `Reader` instance until it reaches an end-of-file marker.
/// Intended for use when parsing the MEMLIST.BIN file in an Another World game directory.
pub fn iterator(reader: anytype) ResourceIterator(@TypeOf(reader)) {
    return ResourceIterator(@TypeOf(reader)) { .reader = reader };
}

fn ResourceIterator(comptime Reader: type) type {
    return struct {
        const Self = @This();

        /// The reader being iterated over.
        reader: Reader,

        /// Returns the next resource descriptor from the reader.
        /// Returns null if it hits an end-of-file marker, or an error if it cannot parse more descriptor data.
        pub fn next(self: *Self) Error(Reader)!?Instance {
            // The layout of each entry in the MEMLIST.BIN file matches the layout of an in-memory data structure
            // which the original Another World executable used for tracking whether a given resource was currently loaded.
            // The contents of the file were poured directly into a contiguous memory block and used as-is for tracking state.
            //
            // Because of this layout, there are gaps in the stored data that corresponded to fields in that in-memory struct: 
            // fields which were used at runtime, but whose values are irrelevant in the file itself.
            // (These fields are expected to be filled with zeroes in MEMLIST.BIN, but we don't actually check.)
            // Our own Instance struct doesn't match this layout, so we just pick out the fields we care about.
            //
            // The layout is as follows (all multibyte fields are big-endian):
            // (Byte offset, size, purpose, description)
            // 0 	u8	loading state	In MEMLIST.BIN: 0, or 255 to mark the end of the list of descriptors.
            // 							In original runtime: tracked the loaded state of the resource:
            // 								0: "not needed, can be cleaned up"
            // 								1: "loaded"
            // 								2: "needs to be loaded"
            // 1	u8	resource type	The type of data in this resource: values correspond to `ResourceType.Enum` members.
            // 2	u16	buffer pointer 	In MEMLIST.BIN: Unused.
            // 							In original runtime: a 16-bit pointer to the location in memory
            //                          at which the resource is loaded.
            // 4	u16	<unknown>		Unknown, apparently unused.
            // 6	u8	load priority	In MEMLIST.BIN: Unused.
            //							In original runtime: used to load resources in order of priority (higher was better).
            // 7	u8	bank ID			Which BANKXX file this resource is located in (from 01-0D).
            // 8	u32	bank offset		The byte offset within the BANK file at which the resource is located.
            // 12	u16	<unknown>		Unknown, apparently unused.
            // 14	u16	packed size		The compressed size of the resource in bytes.
            // 16	u16	<unknown>		Unknown, apparently unused.
            // 18	u16	unpacked size	The final uncompressed size of the resource in bytes.

            const end_of_file_flag = try self.reader.readByte();

            if (end_of_file_flag == end_of_file_marker) {
                return null;
            }

            const raw_type = try self.reader.readByte();
            _ = try self.reader.readInt(u16, .Big);
            _ = try self.reader.readInt(u16, .Big);
            _ = try self.reader.readByte();
            const bank_id = try self.reader.readByte();
            const bank_offset = try self.reader.readInt(u32, .Big);
            _ = try self.reader.readInt(u16, .Big);
            const compressed_size = try self.reader.readInt(u16, .Big);
            _ = try self.reader.readInt(u16, .Big);
            const uncompressed_size = try self.reader.readInt(u16, .Big);

            if (compressed_size > uncompressed_size) {
                return error.InvalidResourceSize;
            }

            return Instance {
                .type = try ResourceType.parse(raw_type),
                .bank_id = bank_id,
                .bank_offset = bank_offset,
                .compressed_size = compressed_size,
                .uncompressed_size = uncompressed_size,
            };
        }
    };
}

/// A 255 byte at the starting position of a descriptor block marks the end of an
/// Another World MEMLIST.BIN resource list.
/// No more descriptors should be parsed after that marker is reached.
const end_of_file_marker: u8 = 0xFF;

// -- Example data --

pub const DescriptorExamples = struct {
    pub const valid_data = [_]u8 {
        // See documentation in `parse` for the expected byte layout.
        0x00,                   // loading state/end-of-file marker
        0x04,                   // resource type (4 == ResourceType.Enum.bytecode)
        0x00, 0x00,             // buffer pointer: unused
        0x00, 0x00,             // unknown: unused
        0x00,                   // priority: unused
        0x05,                   // bank ID (5 == BANK05 file)
        0xDE, 0xAD, 0xBE, 0xEF, // bank offset (big-endian 32-bit unsigned integer)
        0x00, 0x00,             // unknown: unused
        0x8B, 0xAD,             // packed size (big-endian 16-bit unsigned integer)
        0x00, 0x00,             // unknown: unused
        0xF0, 0x0D,             // unpacked size (big-endian 16-bit unsigned integer)
    };

    const invalid_resource_type = block: {
        var invalid_data = valid_data;
        invalid_data[1] = 0xFF; // Does not map to any ResourceType.Enum value
        break :block invalid_data;
    };

    const invalid_resource_size = block: {
        var invalid_data = valid_data;
        // Zero out the unpacked size to ensure that the compressed size is higher
        invalid_data[18] = 0x00;
        invalid_data[19] = 0x00;
        break :block invalid_data;
    };

    const valid_end_of_file = [_]u8 { end_of_file_marker };

    const valid_descriptor = Instance {
        .type = .bytecode,
        .bank_id = 5,
        .bank_offset = 0xDEADBEEF,
        .compressed_size = 0x8BAD,
        .uncompressed_size = 0xF00D,
    };
};

pub const FileExamples = struct {
    pub const valid = (DescriptorExamples.valid_data ** 3) ++ DescriptorExamples.valid_end_of_file;
    pub const truncated = DescriptorExamples.valid_data ** 2;

    pub const invalid_resource_type = 
        DescriptorExamples.valid_data ++ 
        DescriptorExamples.invalid_resource_type ++ 
        DescriptorExamples.valid_end_of_file;
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const fixedBufferStream = @import("std").io.fixedBufferStream;

test "iterator.next() correctly parses file descriptor" {
    var reader = fixedBufferStream(&DescriptorExamples.valid_data).reader();
    var descriptors = iterator(reader);

    testing.expectEqual(DescriptorExamples.valid_descriptor, descriptors.next());
}

test "iterator.next() stops parsing at end-of-file marker" {
    var reader = fixedBufferStream(&DescriptorExamples.valid_end_of_file).reader();
    var descriptors = iterator(reader);

    testing.expectEqual(null, descriptors.next());
}

test "iterator.next() returns error.InvalidResourceType when resource type byte is not recognized" {
    var reader = fixedBufferStream(&DescriptorExamples.invalid_resource_type).reader();
    var descriptors = iterator(reader);

    testing.expectError(error.InvalidResourceType, descriptors.next());
}

test "iterator.next() returns error.InvalidResourceSize when compressed size is larger than uncompressed size" {
    var reader = fixedBufferStream(&DescriptorExamples.invalid_resource_size).reader();
    var descriptors = iterator(reader);

    testing.expectError(error.InvalidResourceSize, descriptors.next());
}

test "iterator.next() returns error.EndOfStream on incomplete data" {
    var reader = fixedBufferStream(DescriptorExamples.valid_data[0..4]).reader();
    var descriptors = iterator(reader);

    testing.expectError(error.EndOfStream, descriptors.next());
}

test "iterator parses all expected descriptors until it reaches end-of-file marker" {
    var reader = fixedBufferStream(&FileExamples.valid).reader();
    var descriptors = iterator(reader);

    while (try descriptors.next()) |descriptor| {
        testing.expectEqual(DescriptorExamples.valid_descriptor, descriptor);
    }

    // Check that it parsed all available bytes from the reader
    testing.expectError(error.EndOfStream, reader.readByte());
}

test "iterator returns error.EndOfStream when it runs out of data before encountering end-of-file marker" {
    var reader = fixedBufferStream(&FileExamples.truncated).reader();
    var descriptors = iterator(reader);

    testing.expectEqual(DescriptorExamples.valid_descriptor, descriptors.next());
    testing.expectEqual(DescriptorExamples.valid_descriptor, descriptors.next());
    testing.expectError(error.EndOfStream, descriptors.next());
}

test "iterator returns error when it reaches invalid data in the middle of stream" {
    var reader = fixedBufferStream(&FileExamples.invalid_resource_type).reader();
    var descriptors = iterator(reader);

    testing.expectEqual(DescriptorExamples.valid_descriptor, descriptors.next());
    testing.expectError(error.InvalidResourceType, descriptors.next());
}
