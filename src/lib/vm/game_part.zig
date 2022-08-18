const anotherworld = @import("../anotherworld.zig");
const intToEnum = @import("utils").meta.intToEnum;

const ResourceID = anotherworld.resources.ResourceID;

/// A raw game part identifier as represented in Another World's bytecode.
const Raw = u16;

/// Defines the parts in an Another World game, which can represent either chapters of gameplay,
/// cinematics, or menu screens. The VM can have a single game part loaded and running at a time.
pub const GamePart = enum(Raw) {
    // zig fmt: off
    copy_protection     = 0x3E80,
    intro_cinematic     = 0x3E81,
    /// Starting in tentacle pool, escaping from beast
    gameplay1           = 0x3E82,
    /// Breaking out of prison
    gameplay2           = 0x3E83,
    /// Fleeing through the caves
    gameplay3           = 0x3E84,
    /// Arena in giant vehicle
    arena_cinematic     = 0x3E85,
    /// Final gameplay section
    gameplay4           = 0x3E86,
    /// Ending and credits sequence
    ending_cinematic    = 0x3E87,
    /// Password entry screen
    password_entry      = 0x3E88,

    const Self = @This();

    /// Given a raw value parsed from Another World bytecode, returns the appropriate game part.
    /// Returns error.invalidGamePart if the raw value was out of range.
    pub fn parse(raw: Raw) Error!Self {
        return intToEnum(Self, raw) catch error.InvalidGamePart;
    }

    /// The IDs of the resources to load for this game part.
    // Copypasta from reference implementation:
    // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/parts.cpp#L14-L27
    pub fn resourceIDs(self: Self) ResourceIDs {
        return switch (self) {
            // zig fmt: off
            .copy_protection    => ResourceIDs.init(0x14, 0x15, 0x16, null),
            .intro_cinematic    => ResourceIDs.init(0x17, 0x18, 0x19, null),
            .gameplay1          => ResourceIDs.init(0x1A, 0x1B, 0x1C, 0x11),
            .gameplay2          => ResourceIDs.init(0x1D, 0x1E, 0x1F, 0x11),
            .gameplay3          => ResourceIDs.init(0x20, 0x21, 0x22, 0x11),
            .arena_cinematic    => ResourceIDs.init(0x23, 0x24, 0x25, null),
            .gameplay4          => ResourceIDs.init(0x26, 0x27, 0x28, 0x11),
            .ending_cinematic   => ResourceIDs.init(0x29, 0x2A, 0x2B, 0x11),
            .password_entry     => ResourceIDs.init(0x7D, 0x7E, 0x7F, null),
            // zig fmt: on
        };
    }

    /// Whether this game part should allow switching to the password entry screeen.
    pub fn allowsPasswordEntry(self: Self) bool {
        return switch (self) {
            // Don't allow the user to enter passwords until they've passed copy protection.
            .copy_protection => false,
            // Don't reactivate the password entry screen while the user is already on it.
            .password_entry => false,
            else => true,
        };
    }

    // - Exported constants -

    /// All game parts in order of occurrence
    pub const all = [@typeInfo(Self).Enum.fields.len]Self{
        .copy_protection,
        .intro_cinematic,
        .gameplay1,
        .gameplay2,
        .gameplay3,
        .arena_cinematic,
        .gameplay4,
        .ending_cinematic,
        .password_entry,
    };

    pub const Error = error{
        /// The bytecode specified an unknown game part.
        InvalidGamePart,
    };
};

/// Defines the resources needed for a specific part of the game.
const ResourceIDs = struct {
    /// The set of palettes used by the game part.
    palettes: ResourceID,
    /// The program to execute for the game part.
    bytecode: ResourceID,
    /// The resource that stores art specific to the game part,
    /// such as scene backgrounds and cinematic animations.
    polygons: ResourceID,
    /// The resource that stores gameplay art like player and enemy animations.
    /// Gameplay parts all use the same animation resource (0x11);
    /// non-interactive parts (e.g. cinematics and menu screens) leave this `null`.
    animations: ?ResourceID = null,

    fn init(raw_palettes_id: ResourceID.Raw, raw_bytecode_id: ResourceID.Raw, raw_polygons_id: ResourceID.Raw, possible_raw_animations_id: ?ResourceID.Raw) ResourceIDs {
        return .{
            .palettes = ResourceID.cast(raw_palettes_id),
            .bytecode = ResourceID.cast(raw_bytecode_id),
            .polygons = ResourceID.cast(raw_polygons_id),
            .animations = if (possible_raw_animations_id) |raw_animations_id|
                ResourceID.cast(raw_animations_id)
            else
                null,
        };
    }
};

// -- Tests --

const testing = @import("utils").testing;

test "ensure everything compiles" {
    testing.refAllDecls(GamePart);
}

test "parse returns expected enum cases" {
    try testing.expectEqual(.copy_protection, GamePart.parse(0x3E80));
    try testing.expectEqual(.intro_cinematic, GamePart.parse(0x3E81));
    try testing.expectEqual(.gameplay1, GamePart.parse(0x3E82));
    try testing.expectEqual(.gameplay2, GamePart.parse(0x3E83));
    try testing.expectEqual(.gameplay3, GamePart.parse(0x3E84));
    try testing.expectEqual(.arena_cinematic, GamePart.parse(0x3E85));
    try testing.expectEqual(.gameplay4, GamePart.parse(0x3E86));
    try testing.expectEqual(.ending_cinematic, GamePart.parse(0x3E87));
    try testing.expectEqual(.password_entry, GamePart.parse(0x3E88));

    try testing.expectError(error.InvalidGamePart, GamePart.parse(0x0000));
    try testing.expectError(error.InvalidGamePart, GamePart.parse(0x3E79));
    try testing.expectError(error.InvalidGamePart, GamePart.parse(0x3E89));
    try testing.expectError(error.InvalidGamePart, GamePart.parse(0xFFFF));
}

test "allowsPasswordEntry returns expected values" {
    try testing.expectEqual(false, GamePart.copy_protection.allowsPasswordEntry());
    try testing.expectEqual(true, GamePart.intro_cinematic.allowsPasswordEntry());
    try testing.expectEqual(true, GamePart.gameplay1.allowsPasswordEntry());
    try testing.expectEqual(true, GamePart.gameplay2.allowsPasswordEntry());
    try testing.expectEqual(true, GamePart.gameplay3.allowsPasswordEntry());
    try testing.expectEqual(true, GamePart.arena_cinematic.allowsPasswordEntry());
    try testing.expectEqual(true, GamePart.gameplay4.allowsPasswordEntry());
    try testing.expectEqual(true, GamePart.ending_cinematic.allowsPasswordEntry());
    try testing.expectEqual(false, GamePart.password_entry.allowsPasswordEntry());
}
