//! This file defines a type for loading resources from a filesystem directory
//! that contains Another World game files.

const ResourceDescriptor = @import("resource_descriptor.zig");
const ResourceID = @import("../values/resource_id.zig");
const Filename = @import("filename.zig");
const decode = @import("../run_length_decoder/decode.zig").decode;

const FixedBuffer = @import("../utils/fixed_buffer.zig");
const introspection = @import("../utils/introspection.zig");

const static_limits = @import("../static_limits.zig");

const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const io = std.io;

/// The maximum number of resource descriptors that will be parsed from the MEMLIST.BIN file
/// in an Another World game directory.
pub const max_resource_descriptors = static_limits.max_resource_descriptors;

/// Creates a new instance that reads game data from the specified directory handle.
/// The handle must have been opened with `.access_sub_paths = true` (the default).
/// The instance does not take ownership of the directory handle; the calling context
/// must ensure the handle stays open for the scope of the instance.
/// Returns an error if the directory did not contain the expected game data files.
pub fn new(dir: *const fs.Dir) !Instance {
    return try Instance.init(dir);
}

pub const Instance = struct {
    /// An handle for the directory that the instance will load files from.
    /// The instance does not own this handle; the parent context is expected to keep it open
    /// for as long as the instance is in scope.
    dir: *const fs.Dir,

    /// The list of resources parsed from the MEMLIST.BIN manifest located in `dir`.
    /// Access this via resourceDescriptors() instead of directly.
    _raw_descriptors: FixedBuffer.Instance(max_resource_descriptors, ResourceDescriptor.Instance),

    /// Initializes a new instance that reads game data from the specified directory handle.
    /// The handle must have been opened with `.access_sub_paths = true` (the default).
    /// The instance does not take ownership of the directory handle; the calling context
    /// must ensure the handle stays open for the scope of the instance.
    /// Returns an error if the directory did not contain the expected game data files.
    fn init(dir: *const fs.Dir) !Instance {
        var self: Instance = .{
            .dir = dir,
            ._raw_descriptors = undefined,
        };

        const list_file = try self.openFile(.resource_list);
        defer list_file.close();

        self._raw_descriptors.len = try readResourceList(&self._raw_descriptors.items, list_file.reader());

        return self;
    }

    /// Read the specified resource from the appropriate BANKXX file into the provided buffer.
    /// Returns a slice representing the portion of `buffer` that contains resource data.
    /// Returns an error if `buffer` was not large enough to hold the data or if the data
    /// could not be read or decompressed.
    /// In the event of an error, `buffer` may contain partially-loaded game data.
    pub fn bufReadResource(self: Instance, buffer: []u8, descriptor: ResourceDescriptor.Instance) ![]const u8 {
        if (buffer.len < descriptor.uncompressed_size) {
            return error.BufferTooSmall;
        }
        const destination = buffer[0..descriptor.uncompressed_size];

        const bank_file = try self.openFile(.{ .bank = descriptor.bank_id });
        // TODO: leave the files open and have a separate close function,
        // since during game loading we expect to read multiple resources from a single bank.
        defer bank_file.close();

        try bank_file.seekTo(descriptor.bank_offset);

        try readAndDecompress(bank_file.reader(), destination, descriptor.compressed_size);
        return destination;
    }

    /// Allocate a buffer and read the specified resource from the appropriate
    /// BANKXX file into it.
    /// Returns a slice that contains the decompressed resource data.
    /// Caller owns the returned slice and must free it with `allocator.free`.
    /// Returns an error if the allocator failed to allocate memory or if the data
    /// could not be read or decompressed.
    pub fn allocReadResource(self: Instance, allocator: mem.Allocator, descriptor: ResourceDescriptor.Instance) ![]const u8 {
        // Create a buffer just large enough to decompress the resource into.
        var destination = try allocator.alloc(u8, descriptor.uncompressed_size);
        errdefer allocator.free(destination);

        return try self.bufReadResource(destination, descriptor);
    }

    /// Allocate a buffer and read the resource with the specified ID
    /// from the appropriate BANKXX file into it.
    /// Returns a slice that contains the decompressed resource data.
    /// Caller owns the returned slice and must free it with `allocator.free`.
    /// Returns an error if the resource ID was invalid, the allocator failed
    /// to allocate memory, or the data could not be read or decompressed.
    pub fn allocReadResourceByID(self: Instance, allocator: mem.Allocator, id: ResourceID.Raw) ![]const u8 {
        return self.allocReadResource(allocator, try self.resourceDescriptor(id));
    }

    /// Returns a list of all valid resource descriptors,
    /// loaded from the MEMLIST.BIN file in the game directory.
    pub fn resourceDescriptors(self: Instance) []const ResourceDescriptor.Instance {
        return self._raw_descriptors.constSlice();
    }

    /// Returns the descriptor matching the specified ID.
    /// Returns an InvalidResourceID error if the ID was out of range.
    pub fn resourceDescriptor(self: Instance, id: ResourceID.Raw) !ResourceDescriptor.Instance {
        try self.validateResourceID(id);
        return self._raw_descriptors.items[id];
    }

    /// Returns an error if the specified resource ID is out of range for this game directory.
    pub fn validateResourceID(self: Instance, id: ResourceID.Raw) !void {
        if (id >= self._raw_descriptors.len) {
            return error.InvalidResourceID;
        }
    }

    // - Private methods -

    /// Given the filename of an Another World data file, opens the corresponding file
    /// in the game directory for reading.
    /// Returns an open file handle, or an error if the file could not be opened.
    fn openFile(self: Instance, filename: Filename.Instance) !fs.File {
        var buffer: Filename.Buffer = undefined;
        const dos_name = filename.dosName(&buffer);
        return try self.dir.openFile(dos_name, .{ .read = true, .write = false });
    }
};

pub const Error = error{
    /// The specified resource ID does not exist in the game's resource list.
    InvalidResourceID,

    /// The provided buffer is not large enough to load the requested resource.
    BufferTooSmall,
};

// -- Helper functions --

/// Loads a list of resource descriptors from the contents of a MEMLIST.BIN file into the provided buffer.
/// Returns the number of descriptors that were parsed into the buffer.
/// Returns an error if the stream was too long, contained invalid descriptor data,
/// or ran out of space in the buffer before parsing completed.
fn readResourceList(buffer: []ResourceDescriptor.Instance, reader: anytype) ResourceListError(@TypeOf(reader))!usize {
    var iterator = ResourceDescriptor.iterator(reader);

    var count: usize = 0;
    while (try iterator.next()) |descriptor| {
        if (count >= buffer.len) return error.BufferTooSmall;

        buffer[count] = descriptor;
        count += 1;
    } else {
        return count;
    }
}

/// The type of errors that can be returned from a call to `readResourceList`.
fn ResourceListError(comptime Reader: type) type {
    return ResourceDescriptor.Error(Reader) || error{
        /// The provided buffer was not large enough to store all the descriptors defined in the file.
        BufferTooSmall,
    };
}

/// Read resource data from a reader into the specified buffer, which is expected
/// to be exactly large enough to hold the data once it is decompressed.
/// If `buffer.len` is larger than `compressed_size`, the data will be decompressed
/// in place to fill the buffer.
/// On success, `buffer` will be filled with uncompressed data.
/// If reading fails, `buffer`'s contents should be treated as invalid.
fn readAndDecompress(reader: anytype, buffer: []u8, compressed_size: usize) ReadAndDecompressError(@TypeOf(reader))!void {
    // Normally this error case will be caught earlier when parsing resource descriptors:
    // See ResourceDescriptor.iterator.next.
    if (compressed_size > buffer.len) {
        return error.InvalidResourceSize;
    }

    var compressed_region = buffer[0..compressed_size];
    try reader.readNoEof(compressed_region);

    // If the data was compressed, decompress it in place.
    if (compressed_size < buffer.len) {
        decode(compressed_region, buffer) catch {
            // Normalize errors to a generic "welp compressed data was invalid somehow"
            // since the specific errors are meaningless to an upstream context.
            return error.InvalidCompressedData;
        };
    }
}

/// The type of errors that can be returned from a call to `readAndDecompress`.
fn ReadAndDecompressError(comptime Reader: type) type {
    const ReaderError = introspection.ErrorType(Reader.readNoEof);

    return ReaderError || error{
        /// Attempted to copy a resource's data into a buffer that was too small for it.
        InvalidResourceSize,
        /// An error occurred when decompressing RLE-encoded data.
        InvalidCompressedData,
    };
}

// -- Test helpers --

const ResourceListExamples = struct {
    const valid = ResourceDescriptor.FileExamples.valid;
    const too_many_descriptors = ResourceDescriptor.DescriptorExamples.valid_data ** (max_resource_descriptors + 1);
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "readAndDecompress reads uncompressed data into buffer" {
    const source = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    const reader = io.fixedBufferStream(&source).reader();

    var destination: [4]u8 = undefined;
    try readAndDecompress(reader, &destination, source.len);

    try testing.expectEqualSlices(u8, &source, &destination);
}

test "readAndDecompress reads compressed data into buffer" {
    // TODO: we need valid fixture data for this
}

test "readAndDecompress returns error.InvalidCompressedData if data could not be decompressed" {
    const source = [_]u8{ 0xDE, 0xAD, 0xBE };
    const reader = io.fixedBufferStream(&source).reader();

    var destination: [4]u8 = undefined;

    try testing.expectError(
        error.InvalidCompressedData,
        readAndDecompress(reader, &destination, source.len),
    );
}

test "readAndDecompress returns error.InvalidResourceSize on mismatched compressed size" {
    const source = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    const reader = io.fixedBufferStream(&source).reader();

    var destination: [3]u8 = undefined;

    try testing.expectError(
        error.InvalidResourceSize,
        readAndDecompress(reader, &destination, source.len),
    );
}

test "readAndDecompress returns error.EndOfStream when source data is truncated" {
    const source = [_]u8{ 0xDE, 0xAD, 0xBE };
    const reader = io.fixedBufferStream(&source).reader();

    var destination: [4]u8 = undefined;

    try testing.expectError(
        error.EndOfStream,
        readAndDecompress(reader, &destination, destination.len),
    );
}

test "readResourceList parses all descriptors from a stream" {
    var reader = io.fixedBufferStream(&ResourceListExamples.valid).reader();

    var buffer: [max_resource_descriptors]ResourceDescriptor.Instance = undefined;
    const count = try readResourceList(&buffer, reader);

    try testing.expectEqual(3, count);
}

test "readResourceList returns error.BufferTooSmall when stream contains too many descriptors for the buffer" {
    var reader = io.fixedBufferStream(&ResourceListExamples.too_many_descriptors).reader();

    var buffer: [max_resource_descriptors]ResourceDescriptor.Instance = undefined;
    try testing.expectError(error.BufferTooSmall, readResourceList(&buffer, reader));
}

// See integration_tests/resource_loading.zig for tests of Instance itself,
// since it relies on Another World's folder structure and resource data.
