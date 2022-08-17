//! Types and operations dealing with built-in opcodes in Another World bytecode.
//! See instruction.zig for how these are mapped to implementations of those opcodes.

const anotherworld = @import("../anotherworld.zig");
const intToEnum = anotherworld.meta.intToEnum;

/// The known opcodes used in Another World's bytecode.
/// These map to individual instruction types, each defined in their own zig file with the same name.
/// See https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter for a list of opccodes
/// (whose names do not match the ones I have chosen here).
pub const Opcode = enum {
    /// A raw opcode as represented in Another World's bytecode.
    pub const Raw = u8;

    const Self = @This();

    const draw_sprite_polygon_mask: Raw = 0b0100_0000;
    const draw_background_polygon_mask: Raw = 0b1000_0000;

    RegisterSet,
    RegisterCopy,
    RegisterAdd,
    RegisterAddConstant,
    Call,
    Return,
    Yield,
    Jump,
    ActivateThread,
    JumpIfNotZero,
    JumpConditional,
    SelectPalette,
    ControlThreads,
    SelectVideoBuffer,
    FillVideoBuffer,
    CopyVideoBuffer,
    RenderVideoBuffer,
    Kill,
    DrawString,
    RegisterSubtract,
    RegisterAnd,
    RegisterOr,
    RegisterShiftLeft,
    RegisterShiftRight,
    ControlSound,
    ControlResources,
    ControlMusic,

    // All lower enum cases map directly to raw byte values from 0 to 26.
    // These two last cases are different: they are marked by the second-to-highest and highest bit
    // of the raw byte respectively, because these instructions treat the lower 6/7 bits of the opcode
    // byte as part of the instruction itself.
    //
    // They need bitmasking via `draw_sprite_polygon_mask and `draw_background_polygon_mask` to identify.
    // As a result, `intToEnum` should *never* be used to construct instances of this enum type directly:
    // instead, always construct the enum using `parse`.
    DrawSpritePolygon,
    DrawBackgroundPolygon,

    /// Convert a raw opcode from Another World bytecode into the corresponding opcode case.
    /// Returns error.InvalidOpcode if the opcode was not recognized.
    pub fn parse(raw_opcode: Raw) Error!Self {
        if (raw_opcode & draw_background_polygon_mask != 0) {
            return .DrawBackgroundPolygon;
        } else if (raw_opcode & draw_sprite_polygon_mask != 0) {
            return .DrawSpritePolygon;
        } else {
            const opcode = intToEnum(Self, raw_opcode) catch return error.InvalidOpcode;

            // Reject raw opcodes that happened to match the exact enum position
            // of the polygon-drawing enum cases, as those are actually invalid.
            if (opcode == .DrawBackgroundPolygon or opcode == .DrawSpritePolygon) {
                return error.InvalidOpcode;
            }

            return opcode;
        }
    }

    /// Converts an opcode case into its raw bytecode representation.
    /// Intended for fixture generation in tests.
    /// This method panics if given DrawSpritePolygon or DrawBackgroundPolygon,
    /// which do not have a single bytecode representation.
    pub fn encode(opcode: Self) Raw {
        switch (opcode) {
            .DrawSpritePolygon, .DrawBackgroundPolygon => @panic("Polygon opcodes cannot be converted to bytecode directly"),
            else => return @enumToInt(opcode),
        }
    }

    pub const Error = error{
        /// Bytecode contained an unrecognized opcode.
        InvalidOpcode,
    };
};

// -- Tests --

const testing = anotherworld.testing;

test "parse returns expected values" {
    try testing.expectEqual(.RegisterSet, Opcode.parse(0));
    try testing.expectEqual(.RegisterCopy, Opcode.parse(1));
    try testing.expectEqual(.RegisterAdd, Opcode.parse(2));
    try testing.expectEqual(.RegisterAddConstant, Opcode.parse(3));
    try testing.expectEqual(.Call, Opcode.parse(4));
    try testing.expectEqual(.Return, Opcode.parse(5));
    try testing.expectEqual(.Yield, Opcode.parse(6));
    try testing.expectEqual(.Jump, Opcode.parse(7));
    try testing.expectEqual(.ActivateThread, Opcode.parse(8));
    try testing.expectEqual(.JumpIfNotZero, Opcode.parse(9));
    try testing.expectEqual(.JumpConditional, Opcode.parse(10));
    try testing.expectEqual(.SelectPalette, Opcode.parse(11));
    try testing.expectEqual(.ControlThreads, Opcode.parse(12));
    try testing.expectEqual(.SelectVideoBuffer, Opcode.parse(13));
    try testing.expectEqual(.FillVideoBuffer, Opcode.parse(14));
    try testing.expectEqual(.CopyVideoBuffer, Opcode.parse(15));
    try testing.expectEqual(.RenderVideoBuffer, Opcode.parse(16));
    try testing.expectEqual(.Kill, Opcode.parse(17));
    try testing.expectEqual(.DrawString, Opcode.parse(18));
    try testing.expectEqual(.RegisterSubtract, Opcode.parse(19));
    try testing.expectEqual(.RegisterAnd, Opcode.parse(20));
    try testing.expectEqual(.RegisterOr, Opcode.parse(21));
    try testing.expectEqual(.RegisterShiftLeft, Opcode.parse(22));
    try testing.expectEqual(.RegisterShiftRight, Opcode.parse(23));
    try testing.expectEqual(.ControlSound, Opcode.parse(24));
    try testing.expectEqual(.ControlResources, Opcode.parse(25));
    try testing.expectEqual(.ControlMusic, Opcode.parse(26));

    try testing.expectEqual(.DrawSpritePolygon, Opcode.parse(0b0100_0000));
    try testing.expectEqual(.DrawSpritePolygon, Opcode.parse(0b0111_1111));
    try testing.expectEqual(.DrawBackgroundPolygon, Opcode.parse(0b1000_0000));
    try testing.expectEqual(.DrawBackgroundPolygon, Opcode.parse(0b1111_1111));

    try testing.expectError(error.InvalidOpcode, Opcode.parse(27));
    try testing.expectError(error.InvalidOpcode, Opcode.parse(63));
}
