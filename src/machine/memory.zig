//! This file defines a type that reads game resources from disk using a ResourceDirectory instance
//! and stores their data into memory, keeping track of their address and managing their lifetime.
//!
//! Another World loads resources in three different stages:
//!
//! - At the start of a new game part, the game unloads all loaded resources and then loads the
//!   bytecode, palettes and polygon resources for that game part into persistent memory locations.
//!   These resources are kept in memory until a new game part is loaded, and pointers to their
//!   locations in memory are shared with the video and program subsystems, which read from them
//!   continuously to render polygons and execute program instructions.
//! - During a game part, program instructions load individual audio resources (music and SFX)
//!   into persistent memory locations. Those resources are kept in memory until a new game part
//!   is loaded or until a program instruction within the current game part unloads all
//!   individually loaded audio resources. The audio subsystem looks up the memory locations
//!   of those resources by ID and reads their data whenever a specific audio is triggered.
//! - During a game part, program instructions load bitmap resources into a temporary location,
//!   then convert the raw bitmap data into an internal format to draw it immediately into
//!   a background video buffer. That same memory location is reused for every bitmap resource
//!   that is loaded; it is never unloaded nor accessed outside of populating a video buffer.

const ResourceDirectory = @import("../resources/resource_directory.zig");
const ResourceID = @import("../values/resource_id.zig");
const ResourceType = @import("../values/resource_type.zig");
const PlanarBitmapResource = @import("../resources/planar_bitmap_resource.zig");
const GamePart = @import("../values/game_part.zig");

const static_limits = @import("../static_limits.zig");

const mem = @import("std").mem;
const fs = @import("std").fs;

/// The memory addresses of resources loaded via `loadGamePart`.
pub const GamePartResourceLocations = struct {
    /// The memory location of the bytecode resource for the game part.
    bytecode: []const u8,
    /// The memory location of the palette resource for the game part.
    palettes: []const u8,
    /// The memory location of the polygon resource for the game part.
    polygons: []const u8,
    /// The memory location of the animation resource for the game part.
    /// `null` if no animations are used by that game part.
    animations: ?[]const u8,
};

/// The type and memory location of a resource that was loaded via `loadIndividualResource`.
pub const IndividualResourceLocation = union(enum) {
    /// An audio resource that was loaded into a persistent location, that will remain valid
    /// until `loadGamePart` or `unloadAllIndividualResources` are called.
    audio: []const u8,
    /// A bitmap that was loaded into a temporary location. The receiver should immediately
    /// load the contents of that buffer into a video buffer, as its contents will be overwritten
    /// the next time a bitmap is loaded.
    temporary_bitmap: []const u8,
};

/// The location of a resource in memory, or null if the resource is not loaded.
pub const PossibleResourceLocation = ?[]const u8;

const bitmap_region_size = PlanarBitmapResource.bytesRequiredForSize(
    static_limits.virtual_screen_width,
    static_limits.virtual_screen_height,
);

const BitmapRegion = [bitmap_region_size]u8;

/// Creates a new instance that uses the specified allocator for allocating memory
/// and loads game data from the specified repository.
/// All resources will begin initially unloaded.
/// The returned instance must be destroyed by calling `deinit`.
pub fn new(allocator: *mem.Allocator, repository: anytype) !Instance(@TypeOf(repository)) {
    return Instance(@TypeOf(repository)).init(allocator, repository);
}

pub fn Instance(comptime Repository: type) type {
    return struct {
        /// The allocator used for loading resources into memory.
        allocator: *mem.Allocator,
        /// The data source to load resource data from: typically a directory on the local filesystem.
        repository: Repository,
        /// The current location of each resource ID in memory, or null if that resource ID is not loaded.
        /// Should not be accessed directly: instead use resourceLocation(id).
        resource_locations: [ResourceDirectory.max_resource_descriptors]PossibleResourceLocation,
        /// The fixed memory region used for temporarily loading bitmap data.
        temporary_bitmap_region: *BitmapRegion,

        const Self = @This();

        /// Creates a new instance that uses the specified allocator for allocating memory
        /// and loads game data from the specified repository.
        /// All resources will begin initially unloaded.
        /// The returned instance must be destroyed by calling `deinit`.
        pub fn init(allocator: *mem.Allocator, repository: Repository) !Self {
            return Self{
                .allocator = allocator,
                .repository = repository,
                .resource_locations = .{null} ** ResourceDirectory.max_resource_descriptors,
                .temporary_bitmap_region = try allocator.create(BitmapRegion),
            };
        }

        /// Free all loaded resources and allocated buffers, invalidating any references to them.
        /// The instance should not be used after this.
        pub fn deinit(self: *Self) void {
            for (self.resource_locations) |possible_location| {
                if (possible_location) |location| {
                    self.allocator.free(location);
                }
            }

            self.allocator.free(self.temporary_bitmap_region);
            self.* = undefined;

            // TODO: handle repository types that have their own deinit methods.
        }

        /// The memory location of the resource with the specified ID, or `null` if the resource is not loaded.
        /// Returns an error if the location is out of range.
        pub fn resourceLocation(self: Self, id: ResourceID.Raw) !PossibleResourceLocation {
            try self.repository.validateResourceID(id);
            return self.resource_locations[id];
        }

        /// Flush all loaded resources from memory, then load the resources for the specified game part.
        /// Returns a structure with the locations of all loaded resources.
        /// Returns an error if loading any game part resource failed.
        ///
        /// If an error occurs, all previously loaded resources will still have been unloaded,
        /// and some resources for the specified game part may remain loaded. In this situation,
        /// it is safe to call `loadGamePart` on the instance again.
        pub fn loadGamePart(self: *Self, game_part: GamePart.Enum) !GamePartResourceLocations {
            for (self.resource_locations) |*location| {
                self.unload(location);
            }

            const resource_ids = game_part.resourceIDs();
            return GamePartResourceLocations{
                .bytecode = try self.loadIfNeeded(resource_ids.bytecode),
                .palettes = try self.loadIfNeeded(resource_ids.palettes),
                .polygons = try self.loadIfNeeded(resource_ids.polygons),
                .animations = if (resource_ids.animations) |resource_id|
                    try self.loadIfNeeded(resource_id)
                else
                    null,
            };
        }

        /// Loads an individual resource by ID if it is not already loaded,
        /// and returns its memory location.
        ///
        /// Returns an error if the specified resource ID is invalid, the resource at that ID
        /// could not be read from disk, or the resource is of a type that can only be loaded
        /// by `loadGamePart` (not individually).
        pub fn loadIndividualResource(self: *Self, id: ResourceID.Raw) !IndividualResourceLocation {
            const descriptor = try self.repository.resourceDescriptor(id);

            return switch (descriptor.type) {
                .sound_or_empty, .music => IndividualResourceLocation{
                    .audio = try self.loadIfNeeded(id),
                },
                .bitmap => IndividualResourceLocation{
                    .temporary_bitmap = try self.repository.bufReadResource(self.temporary_bitmap_region, descriptor),
                },
                .bytecode, .palettes, .polygons, .sprite_polygons => error.GamePartOnlyResourceType,
            };
        }

        /// Unload all resources that have been loaded with `loadIndividualResource`,
        /// invalidating any pointers to the memory locations of those resources.
        /// Any resources that are intrinsic to the current game part will remain loaded.
        pub fn unloadAllIndividualResources(self: *Self) void {
            for (self.repository.resourceDescriptors()) |descriptor, id| {
                switch (descriptor.type) {
                    // These resource types can only be loaded by loadIndividualResource(id).
                    .sound_or_empty, .music, .bitmap => self.unload(&self.resource_locations[id]),
                    // These resource types can only be loaded by loadGamePart(game_part) and should be left alone.
                    .bytecode, .palettes, .polygons, .sprite_polygons => continue,
                }
            }
        }

        // -- Private methods --

        /// Loads a resource into memory if it is not already loaded, and returns its location.
        /// Returns an error if the specified resource ID is invalid or the resource with that ID
        /// could not be read from disk.
        fn loadIfNeeded(self: *Self, id: ResourceID.Raw) ![]const u8 {
            try self.repository.validateResourceID(id);

            if (self.resource_locations[id]) |location| {
                return location;
            } else {
                const location = try self.repository.allocReadResourceByID(self.allocator, id);
                self.resource_locations[id] = location;
                return location;
            }
        }

        /// Unload a resource by reference.
        /// Invalidates any pointer to that resource's location.
        fn unload(self: *Self, possible_location: *PossibleResourceLocation) void {
            if (possible_location.*) |location| {
                self.allocator.free(location);
                possible_location.* = null;
            }
        }
    };
}

pub const Error = error{
    /// `loadIndividualResource` attempted to load a resource that can only be loaded by `loadGamePart`.
    GamePartOnlyResourceType,
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const MockRepository = @import("../resources/mock_repository.zig");
const FailingAllocator = @import("std").testing.FailingAllocator;

const test_descriptors = &MockRepository.FixtureData.descriptors;
const test_repository = MockRepository.Instance.init(test_descriptors, null);
const failing_repository = MockRepository.Instance.init(test_descriptors, error.ChecksumFailed);

test "Ensure everything compiles" {
    testing.refAllDecls(Instance(*ResourceDirectory.Instance));
}

// -- new tests --

test "new creates an instance with no resources loaded" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    try testing.expectEqualSlices(PossibleResourceLocation, &(.{null} ** memory.resource_locations.len), &memory.resource_locations);
}

test "new returns an error if the bitmap region could not be allocated" {
    try testing.expectError(error.OutOfMemory, new(testing.failing_allocator, test_repository));
}

// -- loadIndividualResource tests --

test "loadIndividualResource loads sound resources into shared memory" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    const resource_id = MockRepository.FixtureData.sfx_resource_id;
    const descriptor = try test_repository.resourceDescriptor(resource_id);
    try testing.expectEqual(.sound_or_empty, descriptor.type);

    const location = try memory.loadIndividualResource(resource_id);
    try testing.expectEqualTags(.audio, location);
    try testing.expectEqual(descriptor.uncompressed_size, location.audio.len);
    try testing.expectEqual(location.audio, memory.resourceLocation(resource_id));
}

test "loadIndividualResource loads music resources into shared memory" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    const resource_id = MockRepository.FixtureData.music_resource_id;
    const descriptor = try test_repository.resourceDescriptor(resource_id);
    try testing.expectEqual(.music, descriptor.type);

    const location = try memory.loadIndividualResource(resource_id);
    try testing.expectEqualTags(.audio, location);
    try testing.expectEqual(descriptor.uncompressed_size, location.audio.len);
    try testing.expectEqual(location.audio, memory.resourceLocation(resource_id));
}

test "loadIndividualResource loads bitmap data into temporary bitmap memory" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    const resource_id = MockRepository.FixtureData.bitmap_resource_id;
    const descriptor = try test_repository.resourceDescriptor(resource_id);
    try testing.expectEqual(.bitmap, descriptor.type);

    const location = try memory.loadIndividualResource(resource_id);
    try testing.expectEqualTags(.temporary_bitmap, location);
    try testing.expectEqual(memory.temporary_bitmap_region, location.temporary_bitmap);
    // A bitmap resource's temporary location should not be persisted in the list of loaded resources
    try testing.expectEqual(null, memory.resourceLocation(resource_id));
}

test "loadIndividualResource clobbers temporary bitmap region when another bitmap is loaded" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    const bitmap_1_id = MockRepository.FixtureData.bitmap_resource_id;
    const bitmap_2_id = MockRepository.FixtureData.bitmap_resource_id_2;

    try testing.expectEqual(.bitmap, (try test_repository.resourceDescriptor(bitmap_1_id)).type);
    try testing.expectEqual(.bitmap, (try test_repository.resourceDescriptor(bitmap_2_id)).type);

    const location_1 = try memory.loadIndividualResource(bitmap_1_id);
    try testing.expectEqualTags(.temporary_bitmap, location_1);
    try testing.expectEqual(memory.temporary_bitmap_region, location_1.temporary_bitmap);

    const location_2 = try memory.loadIndividualResource(bitmap_2_id);
    try testing.expectEqualTags(.temporary_bitmap, location_2);
    try testing.expectEqual(location_1.temporary_bitmap, location_2.temporary_bitmap);
}

test "loadIndividualResource returns error.InvalidResourceID on out-of-bounds resource ID" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    const invalid_id = @intCast(ResourceID.Raw, test_repository.resourceDescriptors().len);
    try testing.expectError(error.InvalidResourceID, memory.loadIndividualResource(invalid_id));
}

test "loadIndividualResource returns error.GamePartOnlyResourceType on game-part-only resource types" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    const resource_ids = GamePart.Enum.gameplay1.resourceIDs();
    try testing.expectError(error.GamePartOnlyResourceType, memory.loadIndividualResource(resource_ids.palettes));
    try testing.expectError(error.GamePartOnlyResourceType, memory.loadIndividualResource(resource_ids.bytecode));
    try testing.expectError(error.GamePartOnlyResourceType, memory.loadIndividualResource(resource_ids.polygons));
    try testing.expectError(error.GamePartOnlyResourceType, memory.loadIndividualResource(resource_ids.animations.?));
}

test "loadIndividualResource returns load error from repository" {
    var memory = try new(testing.allocator, failing_repository);
    defer memory.deinit();

    const resource_id = MockRepository.FixtureData.bitmap_resource_id;
    try testing.expectError(error.ChecksumFailed, memory.loadIndividualResource(resource_id));
}

test "loadIndividualResource returns error.OutOfMemory if allocation fails" {
    var fail_on_second_allocation_allocator = FailingAllocator.init(testing.allocator, 1);

    var memory = try new(&fail_on_second_allocation_allocator.allocator, test_repository);
    defer memory.deinit();

    const resource_id = MockRepository.FixtureData.music_resource_id;
    try testing.expectError(error.OutOfMemory, memory.loadIndividualResource(resource_id));
}

test "loadIndividualResource does not allocate additional memory when loading bitmaps" {
    var fail_on_second_allocation_allocator = FailingAllocator.init(testing.allocator, 1);

    var memory = try new(&fail_on_second_allocation_allocator.allocator, test_repository);
    defer memory.deinit();

    const resource_id = MockRepository.FixtureData.bitmap_resource_id;
    _ = try memory.loadIndividualResource(resource_id);
}

test "loadIndividualResource avoids reloading already-loaded audio resources" {
    var counted_repository = MockRepository.Instance.init(test_descriptors, null);

    var memory = try new(testing.allocator, &counted_repository);
    defer memory.deinit();

    try testing.expectEqual(0, counted_repository.read_count);

    const resource_id = MockRepository.FixtureData.music_resource_id;
    const location_of_first_load = try memory.loadIndividualResource(resource_id);

    try testing.expectEqual(1, counted_repository.read_count);

    const location_of_second_load = try memory.loadIndividualResource(resource_id);

    try testing.expectEqual(location_of_first_load, location_of_second_load);
    try testing.expectEqual(1, counted_repository.read_count);
}

test "loadIndividualResource always reloads bitmap resources" {
    var counted_repository = MockRepository.Instance.init(test_descriptors, null);

    var memory = try new(testing.allocator, &counted_repository);
    defer memory.deinit();

    try testing.expectEqual(0, counted_repository.read_count);

    const resource_id = MockRepository.FixtureData.bitmap_resource_id;
    const location_of_first_load = try memory.loadIndividualResource(resource_id);

    try testing.expectEqual(1, counted_repository.read_count);

    const location_of_second_load = try memory.loadIndividualResource(resource_id);

    try testing.expectEqual(location_of_first_load, location_of_second_load);
    try testing.expectEqual(2, counted_repository.read_count);
}

// -- loadGamePart tests --

test "loadGamePart loads expected resources for game part with animations" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    const game_part: GamePart.Enum = .gameplay1;
    const resource_ids = game_part.resourceIDs();
    const locations = try memory.loadGamePart(game_part);

    try testing.expectEqual((try test_repository.resourceDescriptor(resource_ids.palettes)).uncompressed_size, locations.palettes.len);
    try testing.expectEqual((try test_repository.resourceDescriptor(resource_ids.bytecode)).uncompressed_size, locations.bytecode.len);
    try testing.expectEqual((try test_repository.resourceDescriptor(resource_ids.polygons)).uncompressed_size, locations.polygons.len);
    try testing.expectEqual((try test_repository.resourceDescriptor(resource_ids.animations.?)).uncompressed_size, locations.animations.?.len);

    try testing.expectEqual(locations.palettes, try memory.resourceLocation(resource_ids.palettes));
    try testing.expectEqual(locations.bytecode, try memory.resourceLocation(resource_ids.bytecode));
    try testing.expectEqual(locations.polygons, try memory.resourceLocation(resource_ids.polygons));
    try testing.expectEqual(locations.animations, try memory.resourceLocation(resource_ids.animations.?));
}

test "loadGamePart does not load animations for game part without animations" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    const game_part: GamePart.Enum = .copy_protection;
    const resource_ids = game_part.resourceIDs();
    const locations = try memory.loadGamePart(game_part);

    try testing.expectEqual(null, locations.animations);
}

test "loadGamePart unloads any previously loaded game part's resources" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    const first_game_part: GamePart.Enum = .intro_cinematic;
    const second_game_part: GamePart.Enum = .gameplay1;
    const first_game_part_ids = first_game_part.resourceIDs();
    const second_game_part_ids = second_game_part.resourceIDs();

    _ = try memory.loadGamePart(first_game_part);

    try testing.expect((try memory.resourceLocation(first_game_part_ids.palettes)) != null);
    try testing.expect((try memory.resourceLocation(first_game_part_ids.bytecode)) != null);
    try testing.expect((try memory.resourceLocation(first_game_part_ids.polygons)) != null);
    try testing.expectEqual(null, try memory.resourceLocation(second_game_part_ids.palettes));
    try testing.expectEqual(null, try memory.resourceLocation(second_game_part_ids.bytecode));
    try testing.expectEqual(null, try memory.resourceLocation(second_game_part_ids.polygons));
    try testing.expectEqual(null, try memory.resourceLocation(second_game_part_ids.animations.?));

    _ = try memory.loadGamePart(second_game_part);

    try testing.expectEqual(null, try memory.resourceLocation(first_game_part_ids.palettes));
    try testing.expectEqual(null, try memory.resourceLocation(first_game_part_ids.bytecode));
    try testing.expectEqual(null, try memory.resourceLocation(first_game_part_ids.polygons));
    try testing.expect((try memory.resourceLocation(second_game_part_ids.palettes)) != null);
    try testing.expect((try memory.resourceLocation(second_game_part_ids.bytecode)) != null);
    try testing.expect((try memory.resourceLocation(second_game_part_ids.polygons)) != null);
    try testing.expect((try memory.resourceLocation(second_game_part_ids.animations.?)) != null);
}

test "loadGamePart unloads any previously loaded individual resources" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    const sfx_resource_id = MockRepository.FixtureData.sfx_resource_id;
    const music_resource_id = MockRepository.FixtureData.music_resource_id;
    _ = try memory.loadIndividualResource(sfx_resource_id);
    _ = try memory.loadIndividualResource(music_resource_id);
    try testing.expect((try memory.resourceLocation(sfx_resource_id)) != null);
    try testing.expect((try memory.resourceLocation(music_resource_id)) != null);

    _ = try memory.loadGamePart(.gameplay1);

    try testing.expectEqual(null, try memory.resourceLocation(sfx_resource_id));
    try testing.expectEqual(null, try memory.resourceLocation(music_resource_id));
}

test "loadGamePart returns error.InvalidResourceID on out-of-bounds resource ID" {
    // Snip off the descriptor list halfway through the resource IDs for the first game part
    const truncated_repository = MockRepository.Instance.init(test_descriptors[0..0x15], null);

    var memory = try new(testing.allocator, truncated_repository);
    defer memory.deinit();

    try testing.expectError(error.InvalidResourceID, memory.loadGamePart(.copy_protection));
}

test "loadGamePart returns load error from repository" {
    var memory = try new(testing.allocator, failing_repository);
    defer memory.deinit();

    try testing.expectError(error.ChecksumFailed, memory.loadGamePart(.copy_protection));
}

test "loadGamePart returns error.OutOfMemory if allocation fails" {
    var fail_on_second_allocation_allocator = FailingAllocator.init(testing.allocator, 1);

    var memory = try new(&fail_on_second_allocation_allocator.allocator, test_repository);
    defer memory.deinit();

    try testing.expectError(error.OutOfMemory, memory.loadGamePart(.copy_protection));
}

// -- unloadAllIndividualResources tests --

test "unloadAllIndividualResources unloads sound and music resources but leaves game part resources loaded" {
    var memory = try new(testing.allocator, test_repository);
    defer memory.deinit();

    const game_part: GamePart.Enum = .gameplay1;
    const game_part_resource_ids = game_part.resourceIDs();
    const sfx_resource_id = MockRepository.FixtureData.sfx_resource_id;
    const music_resource_id = MockRepository.FixtureData.music_resource_id;

    const game_part_locations = try memory.loadGamePart(game_part);
    const sfx_location = try memory.loadIndividualResource(sfx_resource_id);
    const music_location = try memory.loadIndividualResource(music_resource_id);

    try testing.expectEqual(game_part_locations.palettes, try memory.resourceLocation(game_part_resource_ids.palettes));
    try testing.expectEqual(game_part_locations.bytecode, try memory.resourceLocation(game_part_resource_ids.bytecode));
    try testing.expectEqual(game_part_locations.polygons, try memory.resourceLocation(game_part_resource_ids.polygons));
    try testing.expectEqual(game_part_locations.animations, try memory.resourceLocation(game_part_resource_ids.animations.?));
    try testing.expectEqual(sfx_location.audio, try memory.resourceLocation(sfx_resource_id));
    try testing.expectEqual(music_location.audio, try memory.resourceLocation(music_resource_id));

    memory.unloadAllIndividualResources();

    try testing.expectEqual(game_part_locations.palettes, try memory.resourceLocation(game_part_resource_ids.palettes));
    try testing.expectEqual(game_part_locations.bytecode, try memory.resourceLocation(game_part_resource_ids.bytecode));
    try testing.expectEqual(game_part_locations.polygons, try memory.resourceLocation(game_part_resource_ids.polygons));
    try testing.expectEqual(game_part_locations.animations, try memory.resourceLocation(game_part_resource_ids.animations.?));
    try testing.expectEqual(null, try memory.resourceLocation(sfx_resource_id));
    try testing.expectEqual(null, try memory.resourceLocation(music_resource_id));
}
