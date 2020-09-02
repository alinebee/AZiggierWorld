const ResourceType = @import("resource_type.zig");
const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;

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
    /// The bank file to look for the resource in: in the original release these are numbered from 01 to 0D.
    bank_id: usize,
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

pub const Error = ResourceType.Error || error {
    /// The stream of resource descriptors contained more than the maximum number of entries.
    ResourceListTooLarge,
};

/// Sanity check: stop parsing a resource list when it contains more than this many items.
/// (This is much larger than necessary; another World's actual MEMLIST.BIN file contains ~150 resources.)
const max_resource_descriptors = 1000;

/// Read resource descriptors from an I/O reader until it reaches an end-of-file marker.
/// On success, returns a slice containing the parsed resource descriptors.
/// The caller owns the returned slice.
/// `expected_count` indicates the number of descriptors that the stream is expected to contain;
/// the returned slice may contain less or more than that.
/// Returns an error if the stream contained invalid descriptor data,
/// did not contain an end-of-file marker, or ran out of memory before parsing completed.
pub fn parse(allocator: *mem.Allocator, reader: anytype, expected_count: usize) ![]Instance {
    var list = try ArrayList(Instance).initCapacity(allocator, expected_count);
    errdefer list.deinit();

    while (true) {
        const result = try parseNext(reader);
        switch (result) {
            .descriptor => |descriptor| {
                if (list.items.len >= max_resource_descriptors) {
                    return error.ResourceListTooLarge;
                }
                try list.append(descriptor);
            },
            // Stop reading if-and-when we encounter an end-of-file marker.
            // Another World's MEMLIST.BIN is expected to contain such a marker;
            // if we hit the actual end of the file without encountering it,
            // parseNext will return error.EndOfStream indicating a truncated file.
            .end_of_file => return list.toOwnedSlice(),
        }
    }
}

/// Parse an Another World resource descriptor from a stream of bytes.
/// Consumes 20 bytes from the stream, or 1 byte if the end-of-file marker was encountered.
fn parseNext(reader: anytype) !ParsingResult {
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

    const end_of_file_flag = try reader.readByte();

    if (end_of_file_flag == end_of_file_marker) {
        return .end_of_file;
    }

    const raw_type = try reader.readByte();
    _ = try reader.readInt(u16, .Big);
    _ = try reader.readInt(u16, .Big);
    _ = try reader.readByte();
    const bank_id = try reader.readByte();
    const bank_offset = try reader.readInt(u32, .Big);
    _ = try reader.readInt(u16, .Big);
    const compressed_size = try reader.readInt(u16, .Big);
    _ = try reader.readInt(u16, .Big);
    const uncompressed_size = try reader.readInt(u16, .Big);

    return ParsingResult { .descriptor = Instance {
        .type = try ResourceType.parse(raw_type),
        .bank_id = bank_id,
        .bank_offset = bank_offset,
        .compressed_size = compressed_size,
        .uncompressed_size = uncompressed_size,
    } };
}

/// The result of parsing an individual resource descriptor from a MEMLIST.BIN file.
const ParsingResult = union(enum) {
    /// A descriptor was encountered when parsing.
    descriptor: Instance,
    /// An end-of-file marker was encountered when parsing.
    end_of_file,
};

/// A 255 byte at the starting position of a descriptor block marks the end of an
/// Another World MEMLIST.BIN resource list.
/// No more descriptors should be parsed after that marker is reached.
const end_of_file_marker: u8 = 0xFF;

// -- Example data --

const DescriptorExamples = struct {
    const valid_data = [_]u8 {
        // See documentation in `parse` for the expected byte layout.
        0x00,                   // loading state/end-of-file marker
        0x04,                   // resource type (4 == ResourceType.Enum.bytecode)
        0x00, 0x00,             // buffer pointer: unused
        0x00, 0x00,             // unknown: unused
        0x00,                   // priority: unused
        0x05,                   // bank ID (5 == BANK05 file)
        0xDE, 0xAD, 0xBE, 0xEF, // bank offset (big-endian 32-bit unsigned integer)
        0x00, 0x00,             // unknown: unused
        0x0B, 0xAD,             // packed size (big-endian 16-bit unsigned integer)
        0x00, 0x00,             // unknown: unused
        0xF0, 0x0D,             // unpacked size (big-endian 16-bit unsigned integer)
    };

    const invalid_resource_type = block: {
        var invalid_data = valid_data;
        invalid_data[1] = 0xFF; // Does not map to any ResourceType.Enum value
        break :block invalid_data;
    };

    const valid_end_of_file = [_]u8 { end_of_file_marker };

    const valid_descriptor = Instance {
        .type = .bytecode,
        .bank_id = 5,
        .bank_offset = 0xDEADBEEF,
        .compressed_size = 0x0BAD,
        .uncompressed_size = 0xF00D,
    };
};

const FileExamples = struct {
    const valid = (DescriptorExamples.valid_data ** 3) ++ DescriptorExamples.valid_end_of_file;
    const truncated = DescriptorExamples.valid_data ** 2;
    const too_many_descriptors = DescriptorExamples.valid_data ** (max_resource_descriptors + 1);

    const invalid_resource_type = 
        DescriptorExamples.valid_data ++ 
        DescriptorExamples.invalid_resource_type ++ 
        DescriptorExamples.valid_end_of_file;
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const fixedBufferStream = @import("std").io.fixedBufferStream;

test "parseNext correctly parses file descriptor" {
    var reader = fixedBufferStream(&DescriptorExamples.valid_data).reader();
    const expected = ParsingResult { .descriptor = DescriptorExamples.valid_descriptor };
    testing.expectEqual(expected, parseNext(reader));
    
    // Check that it parsed all available bytes from the reader
    testing.expectError(error.EndOfStream, reader.readByte());
}

test "parseNext returns error on malformed descriptor data" {
    var reader = fixedBufferStream(&DescriptorExamples.invalid_resource_type).reader();
    testing.expectError(error.InvalidResourceType, parseNext(reader));
}

test "parseNext stops parsing at end-of-file marker" {
    var reader = fixedBufferStream(&DescriptorExamples.valid_end_of_file).reader();

    testing.expectEqual(.end_of_file, parseNext(reader));
}

test "parseNext returns error on incomplete data" {
    var reader = fixedBufferStream(DescriptorExamples.valid_data[0..4]).reader();

    testing.expectError(error.EndOfStream, parseNext(reader));
}

test "parse parses all expected descriptors from file data" {
    var reader = fixedBufferStream(&FileExamples.valid).reader();

    const descriptors = try parse(testing.allocator, reader, 3);
    defer testing.allocator.free(descriptors);

    testing.expectEqual(3, descriptors.len);
    testing.expectEqual(DescriptorExamples.valid_descriptor, descriptors[0]);
    testing.expectEqual(DescriptorExamples.valid_descriptor, descriptors[1]);
    testing.expectEqual(DescriptorExamples.valid_descriptor, descriptors[2]);
}

test "parse returns error.OutOfMemory when it runs out of memory" {
    var reader = fixedBufferStream(&FileExamples.valid).reader();

    testing.expectError(error.OutOfMemory, parse(testing.failing_allocator, reader, 3));
}

test "parse returns error.EndOfStream when it runs out of data before encountering an end-of-file marker" {
    var reader = fixedBufferStream(&FileExamples.truncated).reader();

    testing.expectError(error.EndOfStream, parse(testing.allocator, reader, 3));
}

test "parse returns error.ResourceListTooLarge when stream contains too many descriptors" {
    var reader = fixedBufferStream(&FileExamples.too_many_descriptors).reader();

    testing.expectError(error.ResourceListTooLarge, parse(testing.allocator, reader, 3));
}

test "parse returns error.InvalidResourceType when it encounters malformed descriptor data in a file" {
    var reader = fixedBufferStream(&FileExamples.invalid_resource_type).reader();

    testing.expectError(error.InvalidResourceType, parse(testing.allocator, reader, 3));
}