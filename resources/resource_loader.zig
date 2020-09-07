const ResourceDescriptor = @import("resource_descriptor.zig");
const Filename = @import("filename.zig");
const decode = @import("../run_length_decoder/decode.zig").decode;

const std = @import("std");
const mem = std.mem;
const fs = std.fs;

pub const Instance = struct {
    allocator: *mem.Allocator,
    resource_descriptors: []ResourceDescriptor.Instance,
    path: []const u8,

    /// Creates a new resource loader that reads from the specified base path.
    /// Call `deinit` to deinitialize.
    fn init(self: *Instance, allocator: *mem.Allocator, path: []const u8) !void {
        self.allocator = allocator;
        
        self.path = try allocator.dupe(u8, path);
        errdefer allocator.free(self.path);

        const resource_list_path = try resourcePath(allocator, self.path, .resource_list);
        defer allocator.free(resource_list_path);

        self.resource_descriptors = try readResourceList(allocator, resource_list_path);
        errdefer allocator.free(self.resource_descriptors);
    }

    /// Free the memory used by the loader itself.
    /// Any data that was returned by `readResource` is not owned and must be freed separately.
    /// After calling this function, it is an error to use the loader.
    pub fn deinit(self: Instance) void {
        self.allocator.free(self.path);
        self.allocator.free(self.resource_descriptors);
    }

    /// Read the specified resource from the appropriate BANKXX file,
    /// and return a slice initialized by the specified allocator that contains the decompressed resource data.
    /// Caller owns the returned slice.
    /// Returns an error if the data could not be read or decompressed.
    pub fn readResource(self: Instance, data_allocator: *mem.Allocator, descriptor: ResourceDescriptor.Instance) ![]const u8 {
        const bank_path = try resourcePath(self.allocator, self.path, .{ .bank = descriptor.bank_id });
        defer self.allocator.free(bank_path);

        const file = try fs.openFileAbsolute(bank_path, .{ .read = true });
        // TODO: leave the files open and have a separate close function,
        // since during game loading we expect to read multiple resources from a single bank.
        defer file.close();

        try file.seekTo(descriptor.bank_offset);

        // Create a buffer large enough to decompress the resource into.
        var uncompressed_data = try data_allocator.alloc(u8, descriptor.uncompressed_size);
        errdefer data_allocator.free(uncompressed_data);

        try bufReadResource(file.reader(), uncompressed_data, descriptor.compressed_size);
        return uncompressed_data;
    }
};

/// Create a new resource loader that expects to find game resources in the specified directory.
/// Caller owns the returned loader and must free it by calling `deinit`.
/// Returns an error if the specified path is inaccessible.
pub fn new(allocator: *mem.Allocator, game_path: []const u8) !Instance {
    var instance: Instance = undefined;
    try instance.init(allocator, game_path);
    return instance;
}

/// The number of descriptors expected in an Another World MEMLIST.BIN file.
/// Only used as a guide for memory allocation; larger or smaller MEMLIST.BIN files are supported.
const expected_descriptors = 146;

/// Constructs a full path to the specified filename.
fn resourcePath(allocator: *mem.Allocator, game_path: []const u8, filename: Filename.Instance) ![]const u8 {
    const dos_name = try filename.dosName(allocator);
    defer allocator.free(dos_name);

    const paths = [_][]const u8 { game_path, dos_name };
    return try fs.path.join(allocator, &paths);
}

/// Loads a list of resource descriptors from a MEMLIST.BIN file at the specified path.
fn readResourceList(allocator: *mem.Allocator, path: []const u8) ![]ResourceDescriptor.Instance {
    const file = try fs.openFileAbsolute(path, .{ .read = true });
    defer file.close();

    return try ResourceDescriptor.parse(allocator, file.reader(), expected_descriptors);
}

const BufReadResourceError = error {
    InvalidResourceSize,
    InvalidCompressedData,
    EndOfStream,
};

/// The type of errors that can be returned from bufReadResource.
fn bufReadResourceError(comptime reader: type) type {
    const reader_errors = @TypeOf(reader.readNoEof).ReturnType.ErrorSet;
    return reader_errors || error {
        InvalidResourceSize,
        InvalidCompressedData,
    };
}

/// Read resource data from a reader into the specified buffer, decompressing it if necessary.
/// On success, `buffer` will be filled with uncompressed data.
/// If reading fails, `buffer`'s contents should be treated as invalid.
fn bufReadResource(reader: anytype, buffer: []u8, compressed_size: usize) bufReadResourceError(@TypeOf(reader))!void {
    if (compressed_size > buffer.len) {
        return error.InvalidResourceSize;
    }

    var compressed_region = buffer[0..compressed_size];
    const bytes_read = try reader.readNoEof(compressed_region);

    if (compressed_size < buffer.len) {
        // Decompress RLE-compressed data in place.
        decode(compressed_region, buffer) catch {
            // Normalize errors to a generic "welp compressed data was invalid somehow"
            // since the specific errors are meaningless to an upstream context.
            return error.InvalidCompressedData;
        };
    }
}

// -- Tests --

const testing = @import("../utils/testing.zig");
const platform = @import("builtin").os.tag;

const example_game_path = if (platform == .windows) "C:\\Another World\\" else "/path/to/another_world/";

// TODO: write separate resourcePath tests for Windows paths
test "resourcePath allocates and returns expected path to MEMLIST.BIN" {
    const expected_path = if (platform == .windows)
        "C:\\Another World\\MEMLIST.BIN"
    else
        "/path/to/another_world/MEMLIST.BIN"
    ;
    
    const path = try resourcePath(testing.allocator, example_game_path, .resource_list);
    defer testing.allocator.free(path);

    testing.expectEqualStrings(expected_path, path);
}

test "resourcePath allocates and returns expected path to BANKXX file" {
    const expected_path = if (platform == .windows)
        "C:\\Another World\\BANK0A"
    else
        "/path/to/another_world/BANK0A"
    ;

    const path = try resourcePath(testing.allocator, example_game_path, .{ .bank = 0x0A });
    defer testing.allocator.free(path);

    testing.expectEqualStrings(expected_path, path);
}

test "resourcePath returns error.OutOfMemory if memory could not be allocated" {
    testing.expectError(
        error.OutOfMemory,
        resourcePath(testing.failing_allocator, example_game_path, .resource_list),
    );
}

test "bufReadResource reads uncompressed data into buffer" {
    const source = [_]u8 { 0xDE, 0xAD, 0xBE, 0xEF };
    const reader = std.io.fixedBufferStream(&source).reader();

    var destination: [4]u8 = undefined;
    try bufReadResource(reader, &destination, source.len);

    testing.expectEqualSlices(u8, &source, &destination);
}

test "bufReadResource reads compressed data into buffer" {
    // TODO: we need valid fixture data for this
}

test "bufReadResource returns error.InvalidCompressedData if data could not be decompressed" {
    const source = [_]u8 { 0xDE, 0xAD, 0xBE };
    const reader = std.io.fixedBufferStream(&source).reader();

    var destination: [4]u8 = undefined;

    testing.expectError(
        error.InvalidCompressedData,
        bufReadResource(reader, &destination, source.len),
    );
}

test "bufReadResource returns error.InvalidResourceSize on mismatched compressed size" {
    const source = [_]u8 { 0xDE, 0xAD, 0xBE, 0xEF };
    const reader = std.io.fixedBufferStream(&source).reader();

    var destination: [3]u8 = undefined;

    testing.expectError(
        error.InvalidResourceSize,
        bufReadResource(reader, &destination, source.len),
    );
}

test "bufReadResource returns error.EndOfStream when source data is truncated" {
    const source = [_]u8 { 0xDE, 0xAD, 0xBE };
    const reader = std.io.fixedBufferStream(&source).reader();

    var destination: [4]u8 = undefined;

    testing.expectError(
        error.EndOfStream,
        bufReadResource(reader, &destination, destination.len),
    );
}

// See integration_tests/resource_loading.zig for tests of Instance itself,
// since it relies on Another World's folder structure and resource data.
