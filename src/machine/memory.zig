//! This file defines a type that reads game resources from disk using a ResourceDirectory instance
//! and stores their data into memory, keeping track of their address and managing their lifetime.
//!
//! Another World loads resources in three different stages:
//!
//! - At the start of a new game part, the game unloads all loaded resources and then loads the
//!   bytecode, palettes and polygon resources for that game part into persistent memory locations.
//!   These resources are kept in memory until a new game part is loaded, and pointers to their
//!   locations in memory  are shared with the video and program subsystems, which read from them
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

pub const Instance = struct {
    const bitmap_region_size = PlanarBitmapResource.bytesRequiredForSize(
        static_limits.virtual_screen_width,
        static_limits.virtual_screen_height,
    );
    const BitmapRegion = [bitmap_region_size]u8;

    /// The allocator used for loading resources into memory.
    allocator: *mem.Allocator,
    /// The directory that reads resource data from disk.
    repository: *ResourceDirectory.Instance,
    /// The current location of each resource ID in memory, or null if that resource ID is not loaded.
    /// Should not be accessed directly: instead use resourceLocation(id).
    resource_locations: [ResourceDirectory.max_resource_descriptors]PossibleResourceLocation,
    /// The fixed memory region used for temporarily loading bitmap data.
    temporary_bitmap_region: *BitmapRegion,

    const Self = @This();

    /// Creates a new instance that uses the specified allocator for allocating memory
    /// and loads game data from the specified repository.
    /// All resources will begin initially unloaded.
    pub fn init(allocator: *mem.Allocator, repository: *ResourceDirectory.Instance) !Self {
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
    /// If an error occurs, all previously loaded resources will still have been unloaded
    /// and some resources for the specified game part may remain loaded.
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

pub const Error = error{
    /// `loadIndividualResource` attempted to load a resource that can only be loaded by `loadGamePart`.
    GamePartOnlyResourceType,
};

// -- Tests --

const testing = @import("std").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(Instance);
}
