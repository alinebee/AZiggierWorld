const ResourceID = @import("resource_id.zig");

const intToEnum = @import("../../utils/introspection.zig").intToEnum;

// zig fmt: off

/// Defines the parts in an Another World game, which can represent either chapters of gameplay,
/// cinematics, or menu screens. The VM can have a single game part loaded and running at a time.
pub const Enum = enum(Raw) {
    copy_protection = 0x3E80,
    intro_cinematic,
    /// Starting in tentacle pool, escaping from beast
    gameplay1,
    /// Breaking out of prison
    gameplay2,
    /// Fleeing through the caves
    gameplay3,
    /// Arena in giant vehicle
    arena_cinematic,
    /// Final gameplay section
    gameplay4,
    /// Credits sequence?
    gameplay5,
    password_entry,

    /// The IDs of the resources to load for this game part.
    pub fn resourceIDs(self: Enum) ResourceIDs {
        return switch (self) {
            .copy_protection    => .{ .palettes = 0x14, .bytecode = 0x15, .polygons = 0x16 },
            .intro_cinematic    => .{ .palettes = 0x17, .bytecode = 0x18, .polygons = 0x19 },
            .gameplay1          => .{ .palettes = 0x1A, .bytecode = 0x1B, .polygons = 0x1C, .animations = 0x11 },
            .gameplay2          => .{ .palettes = 0x1D, .bytecode = 0x1E, .polygons = 0x1F, .animations = 0x11 },
            .gameplay3          => .{ .palettes = 0x20, .bytecode = 0x21, .polygons = 0x22, .animations = 0x11 },
            .arena_cinematic    => .{ .palettes = 0x23, .bytecode = 0x24, .polygons = 0x25 },
            .gameplay4          => .{ .palettes = 0x26, .bytecode = 0x27, .polygons = 0x28, .animations = 0x11 },
            .gameplay5          => .{ .palettes = 0x29, .bytecode = 0x2A, .polygons = 0x2B, .animations = 0x11 },
            .password_entry     => .{ .palettes = 0x7D, .bytecode = 0x7E, .polygons = 0x7F },
        };
    }
};
// zig fmt: on

/// Defines the resources needed for a specific part of the game.
pub const ResourceIDs = struct {
    /// The set of palettes used by the game part.
    palettes: ResourceID.Raw,
    /// The program to execute for the game part.
    bytecode: ResourceID.Raw,
    /// The resource that stores art specific to the game part,
    /// such as scene backgrounds and cinematic animations.
    polygons: ResourceID.Raw,
    /// The resource that stores gameplay art like player and enemy animations.
    /// Gameplay parts all use the same animation resource (0x11);
    /// non-interactive parts (e.g. cinematics and menu screens) leave this `null`.
    animations: ?ResourceID.Raw = null,
};

/// A raw game part identifier as represented in Another World's bytecode.
pub const Raw = u16;

/// Given a raw value parsed from Another World bytecode, returns the appropriate game part.
/// Returns error.invalidGamePart if the raw value was out of range.
pub fn parse(raw: Raw) Error!Enum {
    return intToEnum(Enum, raw) catch error.InvalidGamePart;
}

pub const Error = error{
    /// The bytecode specified an unknown game part.
    InvalidGamePart,
};

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "parse returns expected enum cases" {
    testing.expectEqual(.copy_protection, parse(0x3E80));
    testing.expectEqual(.intro_cinematic, parse(0x3E81));
    testing.expectEqual(.gameplay1, parse(0x3E82));
    testing.expectEqual(.gameplay2, parse(0x3E83));
    testing.expectEqual(.gameplay3, parse(0x3E84));
    testing.expectEqual(.arena_cinematic, parse(0x3E85));
    testing.expectEqual(.gameplay4, parse(0x3E86));
    testing.expectEqual(.gameplay5, parse(0x3E87));
    testing.expectEqual(.password_entry, parse(0x3E88));

    testing.expectError(error.InvalidGamePart, parse(0x0000));
    testing.expectError(error.InvalidGamePart, parse(0x3E79));
    testing.expectError(error.InvalidGamePart, parse(0x3E89));
    testing.expectError(error.InvalidGamePart, parse(0xFFFF));
}
