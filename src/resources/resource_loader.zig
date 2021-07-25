//! This file defines a type for loading resources from a filesystem directory
//! that contains Another World game files.

const ResourceDescriptor = @import("resource_descriptor.zig");
const ResourceID = @import("../values/resource_id.zig");
const Filename = @import("filename.zig");
const decode = @import("../run_length_decoder/decode.zig").decode;

const introspection = @import("../utils/introspection.zig");

const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const io = std.io;

/// Create a new resource loader that expects to find game resources in the specified directory.
/// Caller owns the returned loader and must free it by calling `deinit`.
/// Returns an error if the specified path is inaccessible or is missing the expected MEMLIST.BIN file.
pub fn new(allocator: *mem.Allocator, game_path: []const u8) !Instance {
    var instance: Instance = undefined;
    try instance.init(allocator, game_path);
    return instance;
}

pub const Instance = struct {
    /// The absolute path of the directory from which game data will be loaded.
    path: []const u8,
    /// The list of resources parsed from the MEMLIST.BIN manifest located in `path`.
    resource_descriptors: []const ResourceDescriptor.Instance,
    /// The allocator used for constructing filesystem paths and storing the list of resources.
    /// This allocator is not used for loading the contents of game resources themselves;
    /// that must be provided on each call to readResourceAlloc and readResourceByIDAlloc.
    allocator: *mem.Allocator,

    /// Initializes a new resource loader that reads from the specified base path.
    /// Call `deinit` to deinitialize.
    /// Returns an error if the specific allocator failed to allocate memory or the specified path
    /// did not contain the expected game data files.
    fn init(self: *Instance, allocator: *mem.Allocator, path: []const u8) !void {
        self.allocator = allocator;

        self.path = try allocator.dupe(u8, path);
        errdefer allocator.free(self.path);

        const list_path = try resourcePath(allocator, self.path, .resource_list);
        defer allocator.free(list_path);

        const list_file = try fs.openFileAbsolute(list_path, .{ .read = true });
        defer list_file.close();

        self.resource_descriptors = try readResourceList(allocator, list_file.reader(), expected_descriptors);
    }

    /// Free the memory used by the loader itself.
    /// Any data that was returned by `readResource` et al is not owned and must be freed separately.
    /// After calling this function, attempting to use the loader will result in undefined behavior.
    pub fn deinit(self: Instance) void {
        self.allocator.free(self.path);
        self.allocator.free(self.resource_descriptors);
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

        const bank_path = try resourcePath(self.allocator, self.path, .{ .bank = descriptor.bank_id });
        defer self.allocator.free(bank_path);

        const file = try fs.openFileAbsolute(bank_path, .{ .read = true });
        // TODO: leave the files open and have a separate close function,
        // since during game loading we expect to read multiple resources from a single bank.
        defer file.close();

        try file.seekTo(descriptor.bank_offset);

        try readAndDecompress(file.reader(), destination, descriptor.compressed_size);
        return destination;
    }

    /// Allocate a buffer and read the specified resource from the appropriate
    /// BANKXX file into it.
    /// Returns a slice that contains the decompressed resource data.
    /// Caller owns the returned slice and must free it with `data_allocator.free`.
    /// Returns an error if the allocator failed to allocate memory or if the data
    /// could not be read or decompressed.
    pub fn allocReadResource(self: Instance, data_allocator: *mem.Allocator, descriptor: ResourceDescriptor.Instance) ![]const u8 {
        // Create a buffer just large enough to decompress the resource into.
        var destination = try data_allocator.alloc(u8, descriptor.uncompressed_size);
        errdefer data_allocator.free(destination);

        return try self.bufReadResource(destination, descriptor);
    }

    /// Read the specified resource with the specified ID from the appropriate BANKXX file
    /// into the provided buffer.
    /// Returns a slice representing the portion of `buffer` that contains resource data.
    /// Returns an error if the resource ID was invalid, the `buffer` was not large enough
    /// to hold the data, or the data could not be read or decompressed.
    /// In the event of an error, `buffer` may contain partially-loaded game data.
    pub fn bufReadResourceByID(self: Instance, buffer: []u8, id: ResourceID.Raw) ![]const u8 {
        return self.bufReadResource(buffer, try self.descriptor(id));
    }

    /// Allocate a buffer and read the resource with the specified ID
    /// from the appropriate BANKXX file into it.
    /// Returns a slice that contains the decompressed resource data.
    /// Caller owns the returned slice and must free it with `data_allocator.free`.
    /// Returns an error if the resource ID was invalid, the allocator failed
    /// to allocate memory, or the data could not be read or decompressed.
    pub fn allocReadResourceByID(self: Instance, data_allocator: *mem.Allocator, id: ResourceID.Raw) ![]const u8 {
        return self.allocReadResource(data_allocator, try self.descriptor(id));
    }

    pub fn descriptor(self: Instance, id: ResourceID.Raw) !ResourceDescriptor.Instance {
        if (id >= self.resource_descriptors.len) {
            return error.InvalidResourceID;
        }
        return self.resource_descriptors[id];
    }
};

pub const Error = error{
    /// The resource ID does not exist in the game's resource list.
    InvalidResourceID,

    /// The provided buffer is not large enough to load the requested resource.
    BufferTooSmall,
};

/// The number of descriptors expected in an Another World MEMLIST.BIN file.
/// Only used as a guide for memory allocation; larger or smaller MEMLIST.BIN files are supported.
const expected_descriptors = 146;

/// Sanity check: stop parsing a resource list when it contains more than this many descriptors.
const max_descriptors = 1000;

/// Constructs a full path to the specified filename.
/// Caller owns the returned slice and must free it using `allocator`.
fn resourcePath(allocator: *mem.Allocator, game_path: []const u8, filename: Filename.Instance) ![]const u8 {
    const dos_name = try filename.dosName(allocator);
    defer allocator.free(dos_name);

    const paths = [_][]const u8{ game_path, dos_name };
    return try fs.path.join(allocator, &paths);
}

/// The type of errors that can be returned from a call to `readResourceList`.
fn ResourceListError(comptime Reader: type) type {
    return ResourceDescriptor.Error(Reader) || error{
        OutOfMemory,

        /// The resource list contained way too many descriptors.
        ResourceListTooLarge,
    };
}

/// Loads a list of resource descriptors from the contents of a MEMLIST.BIN file.
/// Caller owns the returned slice and must free it using `allocator`.
/// `expected_count` indicates the number of descriptors that the stream is expected to contain;
/// this is only a hint, and the returned slice may contain more or fewer than that.
/// Returns an error if the stream was too long, contained invalid descriptor data,
/// or ran out of memory before parsing completed.
fn readResourceList(allocator: *mem.Allocator, reader: anytype, expected_count: usize) ResourceListError(@TypeOf(reader))![]const ResourceDescriptor.Instance {
    var descriptors = try std.ArrayList(ResourceDescriptor.Instance).initCapacity(allocator, expected_count);
    errdefer descriptors.deinit();

    var iterator = ResourceDescriptor.iterator(reader);

    while (try iterator.next()) |descriptor| {
        if (descriptors.items.len >= max_descriptors) {
            return error.ResourceListTooLarge;
        }
        try descriptors.append(descriptor);
    }

    return descriptors.toOwnedSlice();
}

/// The type of errors that can be returned from a call to `bufReadResource`.
fn ResourceError(comptime Reader: type) type {
    const ReaderError = introspection.ErrorType(Reader.readNoEof);

    return ReaderError || error{
        /// Attempted to copy a resource's data into a buffer that was too small for it.
        InvalidResourceSize,
        /// An error occurred when decompressing RLE-encoded data.
        InvalidCompressedData,
    };
}

/// Read resource data from a reader into the specified buffer, decompressing it if necessary.
/// On success, `buffer` will be filled with uncompressed data.
/// If reading fails, `buffer`'s contents should be treated as invalid.
fn readAndDecompress(reader: anytype, buffer: []u8, compressed_size: usize) ResourceError(@TypeOf(reader))!void {
    // Normally this error case will be caught earlier when parsing resource descriptors:
    // See ResourceDescriptor.iterator.next.
    if (compressed_size > buffer.len) {
        return error.InvalidResourceSize;
    }

    var compressed_region = buffer[0..compressed_size];
    const bytes_read = try reader.readNoEof(compressed_region);

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
    const too_many_descriptors = ResourceDescriptor.DescriptorExamples.valid_data ** (max_descriptors + 1);
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const platform = @import("builtin").os.tag;

const example_game_path = if (platform == .windows) "C:\\Another World\\" else "/path/to/another_world/";

test "resourcePath allocates and returns expected path to MEMLIST.BIN" {
    const expected_path = if (platform == .windows)
        "C:\\Another World\\MEMLIST.BIN"
    else
        "/path/to/another_world/MEMLIST.BIN";

    const path = try resourcePath(testing.allocator, example_game_path, .resource_list);
    defer testing.allocator.free(path);

    try testing.expectEqualStrings(expected_path, path);
}

test "resourcePath allocates and returns expected path to BANKXX file" {
    const expected_path = if (platform == .windows)
        "C:\\Another World\\BANK0A"
    else
        "/path/to/another_world/BANK0A";

    const path = try resourcePath(testing.allocator, example_game_path, .{ .bank = 0x0A });
    defer testing.allocator.free(path);

    try testing.expectEqualStrings(expected_path, path);
}

test "resourcePath returns error.OutOfMemory if memory could not be allocated" {
    try testing.expectError(
        error.OutOfMemory,
        resourcePath(testing.failing_allocator, example_game_path, .resource_list),
    );
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

    try testing.expectError(error.OutOfMemory, readResourceList(testing.failing_allocator, reader, 3));
}

test "readResourceList returns error.OutOfMemory when it runs out of memory" {
    var reader = io.fixedBufferStream(&ResourceListExamples.valid).reader();

    try testing.expectError(error.OutOfMemory, readResourceList(testing.failing_allocator, reader, 3));
}

test "readResourceList returns error.ResourceListTooLarge when stream contains too many descriptors" {
    var reader = io.fixedBufferStream(&ResourceListExamples.too_many_descriptors).reader();

    try testing.expectError(error.ResourceListTooLarge, readResourceList(testing.allocator, reader, max_descriptors));
}

// See integration_tests/resource_loading.zig for tests of Instance itself,
// since it relies on Another World's folder structure and resource data.
