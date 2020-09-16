const intToEnum = @import("../utils/introspection.zig").intToEnum;

/// The possible types for an Another World resource.
pub const Enum = enum(u8) {
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
};

pub const Error = error{
    /// An Another World resource list specified an unknown resource type.
    InvalidResourceType,
};

/// A raw ResourceType enum as it is represented in bytecode as a single byte.
pub const Raw = u8;

/// Parse a valid resource type from a raw bytecode value
pub fn parse(raw: Raw) Error!Enum {
    return intToEnum(Enum, raw) catch error.InvalidResourceType;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse parses raw operation types correctly" {
    testing.expectEqual(.sound_or_empty, parse(0));
    testing.expectEqual(.music, parse(1));
    testing.expectEqual(.bitmap, parse(2));
    testing.expectEqual(.palettes, parse(3));
    testing.expectEqual(.bytecode, parse(4));
    testing.expectEqual(.polygons, parse(5));
    testing.expectEqual(.sprite_polygons, parse(6));
    testing.expectError(
        error.InvalidResourceType,
        parse(7),
    );
}
