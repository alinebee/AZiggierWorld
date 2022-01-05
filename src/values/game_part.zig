const ResourceID = @import("resource_id.zig");

const intToEnum = @import("../utils/introspection.zig").intToEnum;

/// Defines the parts in an Another World game, which can represent either chapters of gameplay,
/// cinematics, or menu screens. The VM can have a single game part loaded and running at a time.
// zig fmt: off
pub const Enum = enum(Raw) {
    copy_protection = 0x3E80,
    intro_cinematic = 0x3E81,
    /// Starting in tentacle pool, escaping from beast
    gameplay1       = 0x3E82,
    /// Breaking out of prison
    gameplay2       = 0x3E83,
    /// Fleeing through the caves
    gameplay3       = 0x3E84,
    /// Arena in giant vehicle
    arena_cinematic = 0x3E85,
    /// Final gameplay section
    gameplay4       = 0x3E86,
    /// Credits sequence?
    gameplay5       = 0x3E87,
    /// Password entry screen
    password_entry  = 0x3E88,

    // NOTE: the reference implementation treats both 0x3E88 and 0x3E89 as the password entry screen,
    // but neither of them is referenced by part-loading instructions in bytecode.
    // It's possible the password entry screen needed to be triggered by the VM's host instead.
    // The reference implementation has code to handle keyboard entry in 0x3E89, but not 0x3E88:
    // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/vm.cpp#L590

    /// The IDs of the resources to load for this game part.
    // Copypasta from reference implementation:
    // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/parts.cpp#L14-L27
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
    // zig fmt: on

    /// Whether this game part should allow switching to the password entry screeen.
    pub fn allowsPasswordEntry(self: Enum) bool {
        return switch (self) {
            // Don't allow the user to enter passwords until they've passed copy protection.
            .copy_protection => false,
            // Don't reactivate the password entry screen while the user is already on it.
            .password_entry => false,
            else => true,
        };
    }

    /// All game parts in order of occurrence
    pub const all = [_]Enum{
        // TODO: try populating this via @typeInfo(@This()).Enum.fields
        .copy_protection,
        .intro_cinematic,
        .gameplay1,
        .gameplay2,
        .gameplay3,
        .arena_cinematic,
        .gameplay4,
        .gameplay5,
        .password_entry,
    };
};

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

const testing = @import("../utils/testing.zig");

test "parse returns expected enum cases" {
    try testing.expectEqual(.copy_protection, parse(0x3E80));
    try testing.expectEqual(.intro_cinematic, parse(0x3E81));
    try testing.expectEqual(.gameplay1, parse(0x3E82));
    try testing.expectEqual(.gameplay2, parse(0x3E83));
    try testing.expectEqual(.gameplay3, parse(0x3E84));
    try testing.expectEqual(.arena_cinematic, parse(0x3E85));
    try testing.expectEqual(.gameplay4, parse(0x3E86));
    try testing.expectEqual(.gameplay5, parse(0x3E87));
    try testing.expectEqual(.password_entry, parse(0x3E88));

    try testing.expectError(error.InvalidGamePart, parse(0x0000));
    try testing.expectError(error.InvalidGamePart, parse(0x3E79));
    try testing.expectError(error.InvalidGamePart, parse(0x3E89));
    try testing.expectError(error.InvalidGamePart, parse(0xFFFF));
}

test "allowsPasswordEntry returns expected values" {
    try testing.expectEqual(false, Enum.copy_protection.allowsPasswordEntry());
    try testing.expectEqual(true, Enum.intro_cinematic.allowsPasswordEntry());
    try testing.expectEqual(true, Enum.gameplay1.allowsPasswordEntry());
    try testing.expectEqual(true, Enum.gameplay2.allowsPasswordEntry());
    try testing.expectEqual(true, Enum.gameplay3.allowsPasswordEntry());
    try testing.expectEqual(true, Enum.arena_cinematic.allowsPasswordEntry());
    try testing.expectEqual(true, Enum.gameplay4.allowsPasswordEntry());
    try testing.expectEqual(true, Enum.gameplay5.allowsPasswordEntry());
    try testing.expectEqual(false, Enum.password_entry.allowsPasswordEntry());
}
