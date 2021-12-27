//! Provides a standard interface for accessing Another World resource data from a repository,
//! e.g. a directory on the local filesystem.

const ResourceDescriptor = @import("resource_descriptor.zig");
const ResourceID = @import("../values/resource_id.zig");

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

/// A generic interface for enumerating available resources and loading resource data into buffers.
/// This is passed around as a 'fat pointer', following zig 0.9.0's polymorphic allocator pattern.
pub const Interface = struct {
    implementation: *anyopaque,
    vtable: *const TypeErasedVTable,

    const Self = @This();

    const TypeErasedVTable = struct {
        bufReadResource: fn (self: *anyopaque, buffer: []u8, descriptor: ResourceDescriptor.Instance) anyerror![]const u8,
        resourceDescriptors: fn (self: *anyopaque) []const ResourceDescriptor.Instance,
    };

    /// Create a new type-erased "fat pointer" that reads from a repository of Another World game data.
    /// Intended to be called by repositories to create a reader interface; should not be used directly.
    pub fn init(implementation_ptr: anytype, comptime bufReadResourceFn: fn (self: @TypeOf(implementation_ptr), buffer: []u8, descriptor: ResourceDescriptor.Instance) anyerror![]const u8, comptime resourceDescriptorsFn: fn (self: @TypeOf(implementation_ptr)) []const ResourceDescriptor.Instance) Interface {
        const Implementation = @TypeOf(implementation_ptr);
        const ptr_info = @typeInfo(Implementation);

        assert(ptr_info == .Pointer); // Must be a pointer
        assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer

        const alignment = ptr_info.Pointer.alignment;

        const TypeUnerasedVTable = struct {
            fn bufReadResourceImpl(type_erased_self: *anyopaque, buffer: []u8, descriptor: ResourceDescriptor.Instance) anyerror![]const u8 {
                const self = @ptrCast(Implementation, @alignCast(alignment, type_erased_self));
                return @call(.{ .modifier = .always_inline }, bufReadResourceFn, .{ self, buffer, descriptor });
            }
            fn resourceDescriptorsImpl(type_erased_self: *anyopaque) []const ResourceDescriptor.Instance {
                const self = @ptrCast(Implementation, @alignCast(alignment, type_erased_self));
                return @call(.{ .modifier = .always_inline }, resourceDescriptorsFn, .{self});
            }

            const vtable = TypeErasedVTable{
                .bufReadResource = bufReadResourceImpl,
                .resourceDescriptors = resourceDescriptorsImpl,
            };
        };

        return .{
            .implementation = implementation_ptr,
            .vtable = &TypeUnerasedVTable.vtable,
        };
    }

    /// Read the specified resource from the appropriate BANKXX file into the provided buffer.
    /// Returns a slice representing the portion of `buffer` that contains resource data.
    /// Returns an error if `buffer` was not large enough to hold the data or if the data
    /// could not be read or decompressed.
    /// In the event of an error, `buffer` may contain partially-loaded game data.
    pub fn bufReadResource(self: Self, buffer: []u8, descriptor: ResourceDescriptor.Instance) ![]const u8 {
        return self.vtable.bufReadResource(self.implementation, buffer, descriptor);
    }

    /// Allocate a buffer and read the specified resource from the appropriate
    /// BANKXX file into it.
    /// Returns a slice that contains the decompressed resource data.
    /// Caller owns the returned slice and must free it with `allocator.free`.
    /// Returns an error if the allocator failed to allocate memory or if the data
    /// could not be read or decompressed.
    pub fn allocReadResource(self: Self, allocator: mem.Allocator, descriptor: ResourceDescriptor.Instance) ![]const u8 {
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
    pub fn allocReadResourceByID(self: Self, allocator: mem.Allocator, id: ResourceID.Raw) ![]const u8 {
        return self.allocReadResource(allocator, try self.resourceDescriptor(id));
    }

    /// Returns a list of all valid resource descriptors,
    /// loaded from the MEMLIST.BIN file in the game directory.
    pub fn resourceDescriptors(self: Self) []const ResourceDescriptor.Instance {
        return self.vtable.resourceDescriptors(self.implementation);
    }

    /// Returns the descriptor matching the specified ID.
    /// Returns an InvalidResourceID error if the ID was out of range.
    pub fn resourceDescriptor(self: Self, id: ResourceID.Raw) !ResourceDescriptor.Instance {
        try self.validateResourceID(id);
        return self.resourceDescriptors()[id];
    }

    /// Returns an error if the specified resource ID is out of range for the underlying repository.
    pub fn validateResourceID(self: Self, id: ResourceID.Raw) !void {
        const descriptors = self.resourceDescriptors();
        if (id >= descriptors.len) {
            return error.InvalidResourceID;
        }
    }
};

// -- Test data --

const example_descriptor = ResourceDescriptor.Instance{
    .type = .music,
    .bank_id = 0,
    .bank_offset = 0,
    .compressed_size = 8,
    .uncompressed_size = 16,
};

const example_descriptors = [_]ResourceDescriptor.Instance{example_descriptor};

const MockImplementation = struct {
    call_counts: struct {
        bufReadResource: usize,
        resourceDescriptors: usize,
    } = .{
        .bufReadResource = 0,
        .resourceDescriptors = 0,
    },

    fn _bufReadResource(self: *MockImplementation, buffer: []u8, descriptor: ResourceDescriptor.Instance) ![]const u8 {
        self.call_counts.bufReadResource += 1;

        testing.expectEqual(example_descriptor, descriptor) catch unreachable;
        return buffer;
    }

    fn _resourceDescriptors(self: *MockImplementation) []const ResourceDescriptor.Instance {
        self.call_counts.resourceDescriptors += 1;
        return &example_descriptors;
    }

    pub fn reader(self: *MockImplementation) Interface {
        return Interface.init(self, _bufReadResource, _resourceDescriptors);
    }
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(Interface);
}

test "bufReadResource calls underlying implementation" {
    var repository = MockImplementation{};

    var buffer: [16]u8 = undefined;
    const data = try repository.reader().bufReadResource(&buffer, example_descriptor);

    try testing.expectEqual(&buffer, data);
    try testing.expectEqual(1, repository.call_counts.bufReadResource);
}

test "resourceDescriptors calls underlying implementation" {
    var repository = MockImplementation{};

    const descriptors = repository.reader().resourceDescriptors();
    try testing.expectEqual(1, repository.call_counts.resourceDescriptors);
    try testing.expectEqual(1, descriptors.len);
    try testing.expectEqual(example_descriptor, descriptors[0]);
}

test "allocReadResource calls bufReadResource with suitably sized buffer" {
    var repository = MockImplementation{};
    const data = try repository.reader().allocReadResource(testing.allocator, example_descriptor);
    defer testing.allocator.free(data);

    try testing.expectEqual(example_descriptor.uncompressed_size, data.len);
}

test "allocReadResource returns error when memory cannot be allocated" {
    var repository = MockImplementation{};

    try testing.expectEqual(error.OutOfMemory, repository.reader().allocReadResource(testing.failing_allocator, example_descriptor));
    try testing.expectEqual(0, repository.call_counts.bufReadResource);
}

test "allocReadResourceByID calls bufReadResource with suitably sized buffer for id" {
    var repository = MockImplementation{};
    const data = try repository.reader().allocReadResourceByID(testing.allocator, 0);
    defer testing.allocator.free(data);

    try testing.expectEqual(example_descriptor.uncompressed_size, data.len);
    try testing.expectEqual(1, repository.call_counts.bufReadResource);
}

test "allocReadResourceByID returns error on out of range ID" {
    var repository = MockImplementation{};
    try testing.expectError(error.InvalidResourceID, repository.reader().allocReadResourceByID(testing.allocator, 1));
}

test "resourceDescriptor returns expected descriptor" {
    var repository = MockImplementation{};

    try testing.expectEqual(example_descriptor, repository.reader().resourceDescriptor(0));
    try testing.expectEqual(2, repository.call_counts.resourceDescriptors);
}

test "resourceDescriptor returns error on out of range ID" {
    var repository = MockImplementation{};
    try testing.expectError(error.InvalidResourceID, repository.reader().resourceDescriptor(1));
}

test "validateResourceID returns no error for valid ID" {
    var repository = MockImplementation{};
    try repository.reader().validateResourceID(0);
    try testing.expectEqual(1, repository.call_counts.resourceDescriptors);
}

test "validateResourceID returns error for invalid ID" {
    var repository = MockImplementation{};
    try testing.expectError(error.InvalidResourceID, repository.reader().validateResourceID(1));
    try testing.expectEqual(1, repository.call_counts.resourceDescriptors);
}
