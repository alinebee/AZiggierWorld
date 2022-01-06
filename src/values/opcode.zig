//! Types and operations dealing with built-in opcodes in Another World bytecode.
//! See instruction.zig for how these are mapped to implementations of those opcodes.

const intToEnum = @import("../utils/introspection.zig").intToEnum;

/// A raw opcode as represented in Another World's bytecode.
pub const Raw = u8;

/// The known opcodes used in Another World's bytecode.
/// These map to individual instruction types, each defined in their own zig file with the same name.
/// See https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter for a list of opccodes
/// (whose names do not match the ones I have chosen here).
pub const Enum = enum(Raw) {
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
};

const draw_sprite_polygon_mask: Raw = 0b0100_0000;
const draw_background_polygon_mask: Raw = 0b1000_0000;

pub const Error = error{
    /// Bytecode contained an unrecognized opcode.
    InvalidOpcode,
};

pub fn parse(raw_opcode: Raw) Error!Enum {
    if (raw_opcode & draw_background_polygon_mask != 0) {
        return .DrawBackgroundPolygon;
    } else if (raw_opcode & draw_sprite_polygon_mask != 0) {
        return .DrawSpritePolygon;
    } else {
        const opcode = intToEnum(Enum, raw_opcode) catch return error.InvalidOpcode;

        // Reject raw opcodes that happened to match the exact enum position
        // of the polygon-drawing enum cases, as those are actually invalid.
        if (opcode == .DrawBackgroundPolygon or opcode == .DrawSpritePolygon) {
            return error.InvalidOpcode;
        }

        return opcode;
    }
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse returns expected values" {
    try testing.expectEqual(.RegisterSet, parse(0));
    try testing.expectEqual(.RegisterCopy, parse(1));
    try testing.expectEqual(.RegisterAdd, parse(2));
    try testing.expectEqual(.RegisterAddConstant, parse(3));
    try testing.expectEqual(.Call, parse(4));
    try testing.expectEqual(.Return, parse(5));
    try testing.expectEqual(.Yield, parse(6));
    try testing.expectEqual(.Jump, parse(7));
    try testing.expectEqual(.ActivateThread, parse(8));
    try testing.expectEqual(.JumpIfNotZero, parse(9));
    try testing.expectEqual(.JumpConditional, parse(10));
    try testing.expectEqual(.SelectPalette, parse(11));
    try testing.expectEqual(.ControlThreads, parse(12));
    try testing.expectEqual(.SelectVideoBuffer, parse(13));
    try testing.expectEqual(.FillVideoBuffer, parse(14));
    try testing.expectEqual(.CopyVideoBuffer, parse(15));
    try testing.expectEqual(.RenderVideoBuffer, parse(16));
    try testing.expectEqual(.Kill, parse(17));
    try testing.expectEqual(.DrawString, parse(18));
    try testing.expectEqual(.RegisterSubtract, parse(19));
    try testing.expectEqual(.RegisterAnd, parse(20));
    try testing.expectEqual(.RegisterOr, parse(21));
    try testing.expectEqual(.RegisterShiftLeft, parse(22));
    try testing.expectEqual(.RegisterShiftRight, parse(23));
    try testing.expectEqual(.ControlSound, parse(24));
    try testing.expectEqual(.ControlResources, parse(25));
    try testing.expectEqual(.ControlMusic, parse(26));

    try testing.expectEqual(.DrawSpritePolygon, parse(0b0100_0000));
    try testing.expectEqual(.DrawSpritePolygon, parse(0b0111_1111));
    try testing.expectEqual(.DrawBackgroundPolygon, parse(0b1000_0000));
    try testing.expectEqual(.DrawBackgroundPolygon, parse(0b1111_1111));

    try testing.expectError(error.InvalidOpcode, parse(27));
    try testing.expectError(error.InvalidOpcode, parse(63));
}
