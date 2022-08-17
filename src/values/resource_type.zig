const anotherworld = @import("../lib/anotherworld.zig");
const intToEnum = anotherworld.meta.intToEnum;

const _Raw = u8;

/// The possible types for an Another World resource.
pub const ResourceType = enum(_Raw) {
    /// The resource contains sound effect data.
    /// Descriptors for 0-byte resources also have this type.
    /// Those may be be a file marker of some kind and not intended to be "played"?
    sound_or_empty = 0,

    /// The resource contains music data.
    music = 1,

    /// The resource contains a single bitmap image.
    bitmap = 2,

    /// The resource contains a set of 32 palettes.
    /// In the original release of Another World, each part of the game has its own set of palettes.
    palettes = 3,

    /// The resource contains executable bytecode.
    /// In the original release of Another World, each part of the game has its own bytecode resource.
    bytecode = 4,

    /// The resource contains polygon data for rendering cinematics and world backgrounds.
    /// In the original release of Another World, each part of the game has its own polygon resource.
    polygons = 5,

    /// The resource contains polygon data for rendering player and enemy sprites.
    /// In the original release of Another World, there is only one resource with this type,
    /// which is shared across all parts of the game.
    sprite_polygons = 6,

    /// Parse a valid resource type from a raw bytecode value
    pub fn parse(raw: Raw) Error!ResourceType {
        return intToEnum(ResourceType, raw) catch error.InvalidResourceType;
    }

    pub const Error = error{
        /// An Another World resource list specified an unknown resource type.
        InvalidResourceType,
    };

    /// A raw ResourceType enum as it is represented in bytecode as a single byte.
    pub const Raw = _Raw;
};

// -- Tests --

const testing = anotherworld.testing;

test "parse parses raw operation types correctly" {
    try testing.expectEqual(.sound_or_empty, ResourceType.parse(0));
    try testing.expectEqual(.music, ResourceType.parse(1));
    try testing.expectEqual(.bitmap, ResourceType.parse(2));
    try testing.expectEqual(.palettes, ResourceType.parse(3));
    try testing.expectEqual(.bytecode, ResourceType.parse(4));
    try testing.expectEqual(.polygons, ResourceType.parse(5));
    try testing.expectEqual(.sprite_polygons, ResourceType.parse(6));
    try testing.expectError(
        error.InvalidResourceType,
        ResourceType.parse(7),
    );
}
