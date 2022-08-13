//! A mock equivalent of ResourceDirectory, intended for unit tests
//! that need to test resource-loading pathways but don't want to depend
//! on the presence of real game files.
//!
//! This mock resource repository provides a configurable list of resource descriptors;
//! attempts to load any descriptor will produce either a configurable error,
//! or a pointer to garbage data of an appropriate length for that resource.
//!
//! Use the `reader()` method to get a ResourceReader interface for loading game data.
//! See resource_reader.zig for the available methods on that interface.
//!
//! Usage:
//! ------
//! const resource_descriptors = []ResourceDescriptor { descriptor1, descriptor2...descriptorN };
//! var repository = MockRepository.init(resource_descriptors, null);
//! const reader = repository.reader();
//!
//! const first_resource_descriptor = try reader.resourceDescriptor(0);
//! try testing.expectEqual(0, repository.read_count);
//! const garbage_data = try reader.allocReadResource(testing.allocator, first_resource_descriptor);
//! try testing.expectEqual(1, repository.read_count);

const ResourceReader = @import("resource_reader.zig").ResourceReader;
const ResourceDescriptor = @import("resource_descriptor.zig").ResourceDescriptor;
const ResourceID = @import("../values/resource_id.zig").ResourceID;
const Opcode = @import("../values/opcode.zig").Opcode;

const static_limits = @import("../static_limits.zig");

const mem = @import("std").mem;
const BoundedArray = @import("std").BoundedArray;

const DescriptorStorage = BoundedArray(ResourceDescriptor, static_limits.max_resource_descriptors);

pub const MockRepository = struct {
    /// The list of resources vended by this mock repository.
    /// Access this via reader().resourceDescriptors() instead of directly.
    _raw_descriptors: DescriptorStorage,

    /// When true, `bufReadResource` will fail with error.InvalidCompressedData.
    /// When false, `bufReadResource` will be successful as long as the buffer passed
    /// to it is large enough for the data being allocated.
    read_should_fail: bool,

    /// The number of times a resource has been loaded, whether the load succeeded or failed.
    /// Incremented by calls to reader().bufReadResource() or any of its derived methods.
    read_count: usize = 0,

    const Self = @This();

    /// Create a new mock repository that exposes the specified resource descriptors,
    /// and produces either an error or an appropriately-sized buffer when
    /// a resource load method is called.
    pub fn init(descriptors: []const ResourceDescriptor, read_should_fail: bool) Self {
        return Self{
            ._raw_descriptors = DescriptorStorage.fromSlice(descriptors) catch unreachable,
            .read_should_fail = read_should_fail,
        };
    }

    /// Returns a reader interface for loading game data from this repository.
    pub fn reader(self: *Self) ResourceReader {
        return ResourceReader.init(self, bufReadResource, resourceDescriptors);
    }

    /// Fills the specified buffer with sample game data, and returns a pointer to the region
    /// of the buffer that was filled. The type of data depends on the type of `descriptor`:
    ///
    /// If `descriptor` is a bytecode resource, that region of the buffer will be filled with
    /// a sample valid bytecode program that does nothing but yield.
    ///
    /// If `descriptor` is another kind of resource, it will be filled with a 0xAA bit pattern:
    /// the same pattern that Zig fills `undefined` variables with in debug mode.
    ///
    /// Returns error.BufferTooSmall and leaves the buffer unchanged if the supplied buffer
    /// is not large enough to hold the descriptor's uncompressed size in bytes.
    fn bufReadResource(self: *Self, buffer: []u8, descriptor: ResourceDescriptor) ResourceReader.BufReadResourceError![]const u8 {
        self.read_count += 1;

        if (buffer.len < descriptor.uncompressed_size) {
            return error.BufferTooSmall;
        }

        if (self.read_should_fail) {
            return error.InvalidCompressedData;
        }

        const slice_to_fill = buffer[0..descriptor.uncompressed_size];

        switch (descriptor.type) {
            .bytecode => {
                fill_with_program(slice_to_fill);
            },
            else => {
                fill_with_pattern(slice_to_fill);
            },
        }

        return slice_to_fill;
    }

    /// Returns a list of all resource descriptors provided to the mock repository instance.
    fn resourceDescriptors(self: *const Self) []const ResourceDescriptor {
        return self._raw_descriptors.constSlice();
    }

    /// Fill the specified buffer with a valid program that does nothing but yield,
    /// and - if there's enough space - that loops after the final yield instruction is reached.
    fn fill_with_program(buffer: []u8) void {
        mem.set(u8, buffer, yield_instruction);

        // Only add a loop if there's enough room to fit it in after at least 1 yield.
        if (buffer.len >= minimum_looped_program_length) {
            const loop_index = buffer.len - loop_instruction.len;
            mem.copy(u8, buffer[loop_index..], &loop_instruction);
        }
    }

    fn fill_with_pattern(buffer: []u8) void {
        mem.set(u8, buffer, resource_bit_pattern);
    }

    // -- Exported constants

    var test_repository = MockRepository.init(&TestFixtures.descriptors, false);
    /// A reader for a test repository that can safely load any game part,
    /// albeit with garbage data. Should only be used in tests.
    pub const test_reader = test_repository.reader();

    // Fake resource descriptors that other scripts can use
    // to populate instances of MockRepository.
    pub const Fixtures = TestFixtures;
};

/// The bit pattern to fill non-bytecode resource buffers with.
/// This is 0xAA, the same as Zig uses for `undefined` regions in Debug mode:
/// https://ziglang.org/documentation/0.9.0/#undefined
const resource_bit_pattern: u8 = 0b1010_1010;

/// The program instructions to fill bytecode resource buffers with.
const yield_instruction = @enumToInt(Opcode.Yield);
const loop_instruction = [_]u8{ @enumToInt(Opcode.Jump), 0x0, 0x0 };

const minimum_looped_program_length = loop_instruction.len + 1;

// -- Resource descriptor fixture data --

const TestFixtures = struct {
    const empty_descriptor = ResourceDescriptor{
        .type = .sound_or_empty,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 0,
        .uncompressed_size = 0,
    };

    const sfx_descriptor = ResourceDescriptor{
        .type = .sound_or_empty,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 100,
        .uncompressed_size = 100,
    };

    const music_descriptor = ResourceDescriptor{
        .type = .music,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 100,
        .uncompressed_size = 100,
    };

    const bitmap_descriptor = ResourceDescriptor{
        .type = .bitmap,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 32_000,
        .uncompressed_size = 32_000,
    };

    const palettes_descriptor = ResourceDescriptor{
        .type = .palettes,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 1024,
        .uncompressed_size = 1024,
    };

    const bytecode_descriptor = ResourceDescriptor{
        .type = .bytecode,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = minimum_looped_program_length,
        .uncompressed_size = minimum_looped_program_length,
    };

    const polygons_descriptor = ResourceDescriptor{
        .type = .polygons,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 2000,
        .uncompressed_size = 2000,
    };

    const sprite_polygons_descriptor = ResourceDescriptor{
        .type = .sprite_polygons,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = 2000,
        .uncompressed_size = 2000,
    };

    pub const sfx_resource_id = ResourceID.cast(0x01);
    pub const music_resource_id = ResourceID.cast(0x02);
    pub const bitmap_resource_id = ResourceID.cast(0x03);
    pub const bitmap_resource_id_2 = ResourceID.cast(0x04);
    pub const max_resource_id = ResourceID.cast(0x7F);
    pub const invalid_resource_id = ResourceID.cast(0x80);

    /// A list of fake descriptors with realistic values for resources that are referenced in game parts.
    pub const descriptors = block: {
        var d = [_]ResourceDescriptor{empty_descriptor} ** (invalid_resource_id.index());

        // Drop in individually loadable resources at known offsets
        d[sfx_resource_id.index()] = sfx_descriptor;
        d[music_resource_id.index()] = music_descriptor;
        d[bitmap_resource_id.index()] = bitmap_descriptor;
        d[bitmap_resource_id_2.index()] = bitmap_descriptor;

        // Animation data shared by all game parts
        d[0x11] = sprite_polygons_descriptor;

        // Part-specific data: see game_part.zig

        // GamePart.copy_protection
        d[0x14] = palettes_descriptor;
        d[0x15] = bytecode_descriptor;
        d[0x16] = polygons_descriptor;

        // GamePart.intro_cinematic
        d[0x17] = palettes_descriptor;
        d[0x18] = bytecode_descriptor;
        d[0x19] = polygons_descriptor;

        // GamePart.gameplay1
        d[0x1A] = palettes_descriptor;
        d[0x1B] = bytecode_descriptor;
        d[0x1C] = polygons_descriptor;

        // GamePart.gameplay2
        d[0x1D] = palettes_descriptor;
        d[0x1E] = bytecode_descriptor;
        d[0x1F] = polygons_descriptor;

        // GamePart.gameplay3
        d[0x20] = palettes_descriptor;
        d[0x21] = bytecode_descriptor;
        d[0x22] = polygons_descriptor;

        // GamePart.arena_cinematic
        d[0x23] = palettes_descriptor;
        d[0x24] = bytecode_descriptor;
        d[0x25] = polygons_descriptor;

        // GamePart.gameplay4
        d[0x26] = palettes_descriptor;
        d[0x27] = bytecode_descriptor;
        d[0x28] = polygons_descriptor;

        // GamePart.ending_cinematic
        d[0x29] = palettes_descriptor;
        d[0x2A] = bytecode_descriptor;
        d[0x2B] = polygons_descriptor;

        // GamePart.password_entry
        d[0x7D] = palettes_descriptor;
        d[0x7E] = bytecode_descriptor;
        d[0x7F] = polygons_descriptor;

        break :block d;
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");

const example_descriptor = ResourceDescriptor{
    .type = .music,
    .bank_id = 0,
    .bank_offset = 0,
    .compressed_size = 10,
    .uncompressed_size = 10,
};

test "bufReadResource with music descriptor returns slice of original buffer filled with bit pattern when buffer is appropriate size" {
    var buffer = [_]u8{0} ** (example_descriptor.uncompressed_size * 2);

    // The region of the buffer representing the resource should be filled with the bit pattern
    // for loaded data, and the rest of the buffer left as-is.
    const expected_buffer_contents = [_]u8{resource_bit_pattern} ** example_descriptor.uncompressed_size ++ [_]u8{0x0} ** example_descriptor.uncompressed_size;

    var repository = MockRepository.init(&.{example_descriptor}, false);
    try testing.expectEqual(0, repository.read_count);
    const result = try repository.reader().bufReadResource(&buffer, example_descriptor);
    try testing.expectEqual(@ptrToInt(&buffer), @ptrToInt(result.ptr));
    try testing.expectEqual(example_descriptor.uncompressed_size, result.len);
    try testing.expectEqual(expected_buffer_contents, buffer);
}

test "bufReadResource with bytecode descriptor returns slice of original buffer filled with valid program" {
    const expected_program = [_]u8{
        @enumToInt(Opcode.Yield),
        @enumToInt(Opcode.Yield),
        @enumToInt(Opcode.Jump),
        0x0,
        0x0,
    };

    const example_bytecode_descriptor = ResourceDescriptor{
        .type = .bytecode,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = expected_program.len,
        .uncompressed_size = expected_program.len,
    };

    var buffer: [expected_program.len]u8 = undefined;

    var repository = MockRepository.init(&.{example_descriptor}, false);
    try testing.expectEqual(0, repository.read_count);
    _ = try repository.reader().bufReadResource(&buffer, example_bytecode_descriptor);
    try testing.expectEqual(expected_program, buffer);
}

test "bufReadResource with bytecode descriptor omits loop instruction when buffer is too short" {
    const expected_program = [_]u8{@enumToInt(Opcode.Yield)} ** 3;

    const example_bytecode_descriptor = ResourceDescriptor{
        .type = .bytecode,
        .bank_id = 0,
        .bank_offset = 0,
        .compressed_size = expected_program.len,
        .uncompressed_size = expected_program.len,
    };

    var buffer: [expected_program.len]u8 = undefined;

    var repository = MockRepository.init(&.{example_descriptor}, false);
    try testing.expectEqual(0, repository.read_count);
    _ = try repository.reader().bufReadResource(&buffer, example_bytecode_descriptor);
    try testing.expectEqual(expected_program, buffer);
}

test "bufReadResource returns supplied error and leaves buffer alone when buffer is appropriate size" {
    var buffer = [_]u8{0} ** (example_descriptor.uncompressed_size * 2);
    // The whole buffer should be left untouched.
    const expected_buffer_contents = buffer;

    var repository = MockRepository.init(&.{example_descriptor}, true);
    try testing.expectEqual(0, repository.read_count);
    try testing.expectError(error.InvalidCompressedData, repository.reader().bufReadResource(&buffer, example_descriptor));
    try testing.expectEqual(1, repository.read_count);
    try testing.expectEqual(expected_buffer_contents, buffer);
}

test "bufReadResource returns error.BufferTooSmall if buffer is too small for resource, even if another error was specified" {
    var buffer = [_]u8{0} ** (example_descriptor.uncompressed_size - 1);
    // The whole buffer should be left untouched.
    const expected_buffer_contents = buffer;

    var repository = MockRepository.init(&.{example_descriptor}, true);
    try testing.expectEqual(0, repository.read_count);
    try testing.expectError(error.BufferTooSmall, repository.reader().bufReadResource(&buffer, example_descriptor));
    try testing.expectEqual(1, repository.read_count);
    try testing.expectEqual(expected_buffer_contents, buffer);
}

test "resourceDescriptors returns expected descriptors" {
    var repository = MockRepository.init(&TestFixtures.descriptors, false);

    try testing.expectEqualSlices(ResourceDescriptor, repository.reader().resourceDescriptors(), &TestFixtures.descriptors);
}

test "Ensure everything compiles" {
    testing.refAllDecls(MockRepository);
}
