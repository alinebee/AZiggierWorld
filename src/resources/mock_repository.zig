//! Defines a mock equivalent of ResourceDirectory.Instance for unit tests
//! that need to test resource-loading pathways but don't want to depend
//! on the presence of real game files.
//!
//! This mock resource repository provides a configurable list of resource descriptors;
//! attempts to load any descriptor will produce either a configurable error,
//! or a pointer to garbage data of an appropriate length for that resource.

const ResourceDescriptor = @import("resource_descriptor.zig");
const ResourceID = @import("../values/resource_id.zig");
const FixedBuffer = @import("../utils/fixed_buffer.zig");

const static_limits = @import("../static_limits.zig");

const mem = @import("std").mem;

pub const max_resource_descriptors = static_limits.max_resource_descriptors;

pub const Instance = struct {
    /// The list of resources vended by this mock repository.
    /// Access this via resourceDescriptors() instead of directly.
    _raw_descriptors: FixedBuffer.Instance(max_resource_descriptors, ResourceDescriptor.Instance),

    /// An optional error returned by `bufReadResource` to simulate file-reading or decompression errors.
    /// If `null`, `bufReadResource` will return a success response.
    read_error: ?anyerror,

    /// Create a new mock repository that exposes the specified resource descriptors,
    /// and produces either an error or an appropriately-sized buffer full of garbage when
    /// a resource load method is called.
    pub fn init(descriptors: []const ResourceDescriptor.Instance, read_error: ?anyerror) Instance {
        return Instance{
            ._raw_descriptors = FixedBuffer.new(max_resource_descriptors, ResourceDescriptor.Instance, descriptors),
            .read_error = read_error,
        };
    }

    /// Leaves the contents of the supplied buffer unchanged, and returns a pointer to the region
    /// of the buffer that would have been filled by resource data in a real implementation.
    /// Returns error.BufferTooSmall if the supplied buffer would not have been large enough
    /// to hold the real resource.
    pub fn bufReadResource(self: Instance, buffer: []u8, descriptor: ResourceDescriptor.Instance) ![]const u8 {
        if (buffer.len < descriptor.uncompressed_size) {
            return error.BufferTooSmall;
        }

        return self.read_error orelse buffer[0..descriptor.uncompressed_size];
    }

    /// Allocate and return a buffer large enough to store the specified resource.
    /// This buffer will be filled with garbage rather than parseable resource data.
    /// Returns an error if the allocator could not allocate memory for the buffer.
    pub fn allocReadResource(self: Instance, allocator: *mem.Allocator, descriptor: ResourceDescriptor.Instance) ![]const u8 {
        // Create a buffer just large enough to decompress the resource into.
        var destination = try allocator.alloc(u8, descriptor.uncompressed_size);
        errdefer allocator.free(destination);

        return try self.bufReadResource(destination, descriptor);
    }

    /// Allocate and return a buffer large enough to store the resource with the specified ID.
    /// This buffer will be filled with garbage rather than parseable resource data.
    /// Returns an error if the resource ID was invalid.
    pub fn allocReadResourceByID(self: Instance, allocator: *mem.Allocator, id: ResourceID.Raw) ![]const u8 {
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
};

// -- Resource descriptor fixture data --

pub const FixtureData = struct {
    const empty_descriptor = ResourceDescriptor.Instance{
        .type = .sound_or_empty,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 0,
        .uncompressed_size = 0,
    };

    const sfx_descriptor = ResourceDescriptor.Instance{
        .type = .sound_or_empty,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 100,
        .uncompressed_size = 100,
    };

    const music_descriptor = ResourceDescriptor.Instance{
        .type = .music,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 100,
        .uncompressed_size = 100,
    };

    const bitmap_descriptor = ResourceDescriptor.Instance{
        .type = .bitmap,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 32_000,
        .uncompressed_size = 32_000,
    };

    const palettes_descriptor = ResourceDescriptor.Instance{
        .type = .palettes,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 1024,
        .uncompressed_size = 1024,
    };

    const bytecode_descriptor = ResourceDescriptor.Instance{
        .type = .bytecode,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 2000,
        .uncompressed_size = 2000,
    };

    const polygons_descriptor = ResourceDescriptor.Instance{
        .type = .polygons,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 2000,
        .uncompressed_size = 2000,
    };

    const sprite_polygons_descriptor = ResourceDescriptor.Instance{
        .type = .sprite_polygons,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 2000,
        .uncompressed_size = 2000,
    };

    pub const sfx_resource_id = 0x01;
    pub const music_resource_id = 0x02;
    pub const bitmap_resource_id = 0x03;
    pub const bitmap_resource_id_2 = 0x04;

    /// A list of fake descriptors with realistic values for resources that are referenced in game parts.
    pub const descriptors = block: {
        const max_resource_id = 0x7F;
        var d = [_]ResourceDescriptor.Instance{empty_descriptor} ** (max_resource_id + 1);

        // Drop in individually loadable resources at known offsets
        d[sfx_resource_id] = sfx_descriptor;
        d[music_resource_id] = music_descriptor;
        d[bitmap_resource_id] = bitmap_descriptor;
        d[bitmap_resource_id_2] = bitmap_descriptor;

        // Animation data shared by all game parts
        d[0x11] = sprite_polygons_descriptor;

        // Part-specific data: see game_part.zig

        // GamePart.Enum.copy_protection
        d[0x14] = palettes_descriptor;
        d[0x15] = bytecode_descriptor;
        d[0x16] = polygons_descriptor;

        // GamePart.Enum.intro_cinematic
        d[0x17] = palettes_descriptor;
        d[0x18] = bytecode_descriptor;
        d[0x19] = polygons_descriptor;

        // GamePart.Enum.gameplay1
        d[0x1A] = palettes_descriptor;
        d[0x1B] = bytecode_descriptor;
        d[0x1C] = polygons_descriptor;

        // GamePart.Enum.gameplay2
        d[0x1D] = palettes_descriptor;
        d[0x1E] = bytecode_descriptor;
        d[0x1F] = polygons_descriptor;

        // GamePart.Enum.gameplay3
        d[0x20] = palettes_descriptor;
        d[0x21] = bytecode_descriptor;
        d[0x22] = polygons_descriptor;

        // GamePart.Enum.arena_cinematic
        d[0x23] = palettes_descriptor;
        d[0x24] = bytecode_descriptor;
        d[0x25] = polygons_descriptor;

        // GamePart.Enum.gameplay4
        d[0x26] = palettes_descriptor;
        d[0x27] = bytecode_descriptor;
        d[0x28] = polygons_descriptor;

        // GamePart.Enum.gameplay5
        d[0x29] = palettes_descriptor;
        d[0x2A] = bytecode_descriptor;
        d[0x2B] = polygons_descriptor;

        // GamePart.Enum.password_entry
        d[0x7D] = palettes_descriptor;
        d[0x7E] = bytecode_descriptor;
        d[0x7F] = polygons_descriptor;

        break :block d;
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");

const example_descriptor = ResourceDescriptor.Instance{
    .type = .bytecode,
    .bank_id = 0,
    .bank_offset = 0,
    .compressed_size = 10,
    .uncompressed_size = 10,
};

test "bufReadResource returns slice of original buffer when buffer is appropriate size" {
    const repository = Instance.init(&.{example_descriptor}, null);

    var buffer = try testing.allocator.alloc(u8, example_descriptor.uncompressed_size * 2);
    defer testing.allocator.free(buffer);

    const result = try repository.bufReadResource(buffer, example_descriptor);
    try testing.expectEqual(@ptrToInt(result.ptr), @ptrToInt(buffer.ptr));
    try testing.expectEqual(result.len, example_descriptor.uncompressed_size);
}

test "bufReadResource returns supplied error when buffer is appropriate size" {
    const repository = Instance.init(&.{example_descriptor}, error.ChecksumFailed);

    var buffer = try testing.allocator.alloc(u8, example_descriptor.uncompressed_size * 2);
    defer testing.allocator.free(buffer);

    try testing.expectError(error.ChecksumFailed, repository.bufReadResource(buffer, example_descriptor));
}

test "bufReadResource returns error.BufferTooSmall if buffer is too small for resource, even if another error was specified" {
    const repository = Instance.init(&.{example_descriptor}, error.ChecksumFailed);

    var buffer = try testing.allocator.alloc(u8, example_descriptor.uncompressed_size / 2);
    defer testing.allocator.free(buffer);

    try testing.expectError(error.BufferTooSmall, repository.bufReadResource(buffer, example_descriptor));
}

test "resourceDescriptors returns expected descriptors" {
    const repository = Instance.init(&FixtureData.descriptors, null);

    try testing.expectEqualSlices(ResourceDescriptor.Instance, repository.resourceDescriptors(), &FixtureData.descriptors);
}

test "resourceDescriptor returns expected descriptor by ID" {
    const repository = Instance.init(&FixtureData.descriptors, null);

    try testing.expectEqual(FixtureData.sprite_polygons_descriptor, repository.resourceDescriptor(0x11));
}

test "validateResourceDescriptor returns no error for resource ID in range" {
    const repository = Instance.init(&FixtureData.descriptors, null);

    try repository.validateResourceID(FixtureData.descriptors.len - 1);
}

test "validateResourceDescriptor returns no error for resource ID in range" {
    const repository = Instance.init(&FixtureData.descriptors, null);

    try testing.expectError(error.InvalidResourceID, repository.validateResourceID(FixtureData.descriptors.len));
}

test "Ensure everything compiles" {
    testing.refAllDecls(Instance);
}
