//! A type representing a filesystem directory that contains Another World game files.
//! An instance of this type is intended to be created at game launch and kept around
//! for the lifetime of the game.
//!
//! Use the `reader()` method to get a Reader interface for loading game data.
//! See reader.zig for the available methods on that interface.
//!
//! Usage:
//! ------
//! const game_dir = try std.fs.openDirAbsolute("/path/to/another/world/", .{});
//! defer game_dir.close();
//! var repository = try ResourceDirectory.new(game_dir);
//! const reader = repository.reader();
//! const first_resource_descriptor = try reader.resourceDescriptor(0);
//! const game_data = try reader.allocReadResource(my_allocator, first_resource_descriptor);

const Reader = @import("reader.zig");
const ResourceDescriptor = @import("resource_descriptor.zig");
const ResourceID = @import("../values/resource_id.zig");
const Filename = @import("filename.zig");
const decode = @import("../run_length_decoder/decode.zig").decode;

const introspection = @import("../utils/introspection.zig");
const log = @import("../utils/logging.zig").log;

const static_limits = @import("../static_limits.zig");

const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const io = std.io;

/// The maximum number of resource descriptors that will be parsed from the MEMLIST.BIN file
/// in an Another World game directory.
pub const max_resource_descriptors = static_limits.max_resource_descriptors;
const DescriptorStorage = std.BoundedArray(ResourceDescriptor.Instance, max_resource_descriptors);

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
    _raw_descriptors: DescriptorStorage,

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

        self._raw_descriptors.len = try readResourceList(&self._raw_descriptors.buffer, list_file.reader());

        return self;
    }

    /// Returns a reader interface for loading game data from this repository.
    pub fn reader(self: *Instance) Reader.Interface {
        return Reader.Interface.init(self, bufReadResource, resourceDescriptors);
    }

    // - Private methods -

    /// Read the specified resource from the appropriate BANKXX file into the provided buffer.
    /// Returns a slice representing the portion of `buffer` that contains resource data.
    /// Returns an error if `buffer` was not large enough to hold the data or if the data
    /// could not be read or decompressed.
    /// In the event of an error, `buffer` may contain partially-loaded game data.
    fn bufReadResource(self: *const Instance, buffer: []u8, descriptor: ResourceDescriptor.Instance) Reader.BufReadResourceError![]const u8 {
        if (buffer.len < descriptor.uncompressed_size) {
            return error.BufferTooSmall;
        }

        const bank_file = self.openFile(.{ .bank = descriptor.bank_id }) catch |err| {
            log.err("Could not open file for bank {}: {}", .{ descriptor.bank_id, err });
            return error.RepositorySpecificFailure;
        };

        // TODO: leave the files open and have a separate close function,
        // since during game loading we expect to read multiple resources from a single bank.
        defer bank_file.close();

        bank_file.seekTo(descriptor.bank_offset) catch |err| {
            log.err("Could not seek file for bank {} to offset {}: {}", .{ descriptor.bank_id, descriptor.bank_offset, err });
            return error.RepositorySpecificFailure;
        };

        const destination = buffer[0..descriptor.uncompressed_size];
        try readAndDecompress(bank_file.reader(), destination, descriptor.compressed_size);

        return destination;
    }

    /// Returns a list of all valid resource descriptors,
    /// loaded from the MEMLIST.BIN file in the game directory.
    fn resourceDescriptors(self: *const Instance) []const ResourceDescriptor.Instance {
        return self._raw_descriptors.constSlice();
    }

    /// Given the filename of an Another World data file, opens the corresponding file
    /// in the game directory for reading.
    /// Returns an open file handle, or an error if the file could not be opened.
    fn openFile(self: Instance, filename: Filename.Instance) !fs.File {
        var buffer: Filename.Buffer = undefined;
        const dos_name = filename.dosName(&buffer);
        return try self.dir.openFile(dos_name, .{ .read = true, .write = false });
    }
};

// -- Helper functions --

/// Loads a list of resource descriptors into the provided buffer, from a byte stream
/// representing the contents of a MEMLIST.BIN file.
/// Returns the number of descriptors that were parsed into the buffer.
/// Returns an error if the stream was too long, contained invalid descriptor data,
/// or ran out of space in the buffer before parsing completed.
fn readResourceList(buffer: []ResourceDescriptor.Instance, io_reader: anytype) ResourceListError(@TypeOf(io_reader))!usize {
    var iterator = ResourceDescriptor.iterator(io_reader);

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
fn ResourceListError(comptime IOReader: type) type {
    return ResourceDescriptor.Error(IOReader) || error{
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
fn readAndDecompress(reader: anytype, buffer: []u8, compressed_size: usize) Reader.BufReadResourceError!void {
    // Normally this error case will be caught earlier when parsing resource descriptors:
    // See ResourceDescriptor.iterator.next.
    if (compressed_size > buffer.len) {
        return error.InvalidResourceSize;
    }

    const compressed_region = buffer[0..compressed_size];
    reader.readNoEof(compressed_region) catch |err| {
        // Convert filesystem-specific errors into generic repository reader errors.
        return switch (err) {
            error.EndOfStream => error.TruncatedData,
            else => error.RepositorySpecificFailure,
        };
    };

    // If the data was compressed, decompress it in place.
    if (compressed_size < buffer.len) {
        decode(compressed_region, buffer) catch {
            // Normalize errors to a generic "welp compressed data was invalid somehow"
            // since the specific errors are meaningless to an upstream context.
            return error.InvalidCompressedData;
        };
    }
}

// -- Test helpers --

const ResourceListExamples = struct {
    const valid = ResourceDescriptor.FileExamples.valid;
    const too_many_descriptors = ResourceDescriptor.DescriptorExamples.valid_data ** (max_resource_descriptors + 1);
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "ensure everything compiles" {
    testing.refAllDecls(Instance);
}

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

test "readAndDecompress returns error.TruncatedData when source data is truncated" {
    const source = [_]u8{ 0xDE, 0xAD, 0xBE };
    const reader = io.fixedBufferStream(&source).reader();

    var destination: [4]u8 = undefined;

    try testing.expectError(
        error.TruncatedData,
        readAndDecompress(reader, &destination, destination.len),
    );
}

test "readAndDecompress returns error.RepositorySpecificFailure when reader produced a non-EndOfStream error" {
    // TODO: write a reader that will do this.
}

test "readResourceList parses all descriptors from a stream" {
    const reader = io.fixedBufferStream(&ResourceListExamples.valid).reader();

    var buffer: [max_resource_descriptors]ResourceDescriptor.Instance = undefined;
    const count = try readResourceList(&buffer, reader);

    try testing.expectEqual(3, count);
}

test "readResourceList returns error.BufferTooSmall when stream contains too many descriptors for the buffer" {
    const reader = io.fixedBufferStream(&ResourceListExamples.too_many_descriptors).reader();

    var buffer: [max_resource_descriptors]ResourceDescriptor.Instance = undefined;
    try testing.expectError(error.BufferTooSmall, readResourceList(&buffer, reader));
}

// See integration_tests/resource_loading.zig for tests of Instance itself,
// since it relies on Another World's folder structure and resource data.
