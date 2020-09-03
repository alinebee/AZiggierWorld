const ResourceDescriptor = @import("resource_descriptor.zig");
const Filename = @import("filename.zig");
const decode = @import("run_length_decoder.zig").decode;

const std = @import("std");
const mem = std.mem;
const fs = std.fs;

pub const Instance = struct {
    allocator: *mem.Allocator,
    resource_descriptors: []ResourceDescriptor.Instance,
    path: []const u8,

    /// Creates a new resource loader that reads from the specified base path.
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
        // Guard against mismatched sizes in the descriptor,
        // which would otherwise cause an out-of-bounds error below when slicing the buffer.
        if (descriptor.compressed_size > descriptor.uncompressed_size) {
            return error.InvalidResourceSize;
        }

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

        // Read the compressed data into the start of the buffer.
        const compressed_data = uncompressed_data[0..descriptor.compressed_size];
        const bytes_read = try file.readAll(compressed_data);

        if (bytes_read < compressed_data.len) {
            return error.EndOfStream;
        }

        if (descriptor.isCompressed()) {
            // Decompress RLE-compressed data in place.
            try decode(compressed_data, uncompressed_data);
        }

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

// -- Tests --

const testing = @import("../utils/testing.zig");

// TODO: write separate resourcePath tests for Windows paths
test "resourcePath allocates and returns expected path to MEMLIST.BIN" {
    const game_path = "/path/to/another_world/";

    const path = try resourcePath(testing.allocator, game_path, .resource_list);
    defer testing.allocator.free(path);

    testing.expectEqualStrings("/path/to/another_world/MEMLIST.BIN", path);
}

test "resourcePath allocates and returns expected path to BANKXX file" {
    const game_path = "/path/to/another_world/";

    const path = try resourcePath(testing.allocator, game_path, .{ .bank = 0x0A });
    defer testing.allocator.free(path);

    testing.expectEqualStrings("/path/to/another_world/BANK0A", path);
}

test "resourcePath returns error.OutOfMemory if memory could not be allocated" {
    const game_path = "/path/to/another_world/";

    testing.expectError(
        error.OutOfMemory,
        resourcePath(testing.failing_allocator, game_path, .resource_list),
    );
}

// See integration_tests/resource_loading.zig for tests of Instance itself,
// since it depends heavily on access to real game files.