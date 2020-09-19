const intToEnum = @import("../../utils/introspection.zig").intToEnum;

//! Types and operations dealing with built-in opcodes in Another World bytecode.
//! See instruction.zig for how these are mapped to implementations of those opcodes.

/// A raw opcode as represented in Another World's bytecode.
pub const Raw = u8;

/// The known opcodes used in Another World's bytecode.
/// These map to individual instruction types, each defined in their own zig file with the same name.
/// See https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter for a list of opccodes
/// (whose names do not match the ones I have chosen here).
pub const Enum = enum(Raw) {
    SetRegister,
    CopyRegister,
    AddToRegister,
    AddConstantToRegister,
    Call,
    Return,
    Yield,
    Jump,
    ActivateThread,
    JumpIfNotZero,
    ConditionalJump,
    SetPalette,
    ControlThreads,
    SelectVideoBuffer,
    FillVideoBuffer,
    CopyVideoBuffer,
    RenderVideoBuffer,
    KillThread,
    DrawString,
    SubstractFromRegister,
    AndRegister,
    OrRegister,
    ShiftRegisterLeft,
    ShiftRegisterRight,
    ControlSound,
    ControlResources,
    ControlMusic,

    // All lower enum cases map directly to raw byte values from 0 to 26.
    // These two last cases are different: they are marked by the second-to-highest and highest bit
    // respectively, because these instructions treat the lower 6/7 bits of the opcode as part of the
    // instruction itself.
    // They need bitmasking to identity: the values here are their bitmasks rather than discrete values.
    // As a result `intToEnum` should never be used to construct instances of this enum type directly:
    // instead, always construct the enum using `parse`.
    DrawSpritePolygon = 0b0100_0000,
    DrawBackgroundPolygon = 0b1000_0000,
};

pub const Error = error{
    /// Bytecode contained an unrecognized opcode.
    InvalidOpcode,
};

pub fn parse(raw_opcode: Raw) Error!Enum {
    if (raw_opcode & @enumToInt(Enum.DrawBackgroundPolygon) != 0) {
        return .DrawBackgroundPolygon;
    } else if (raw_opcode & @enumToInt(Enum.DrawSpritePolygon) != 0) {
        return .DrawSpritePolygon;
    } else {
        return intToEnum(Enum, raw_opcode) catch error.InvalidOpcode;
    }
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "parse returns expected values" {
    testing.expectEqual(.SetRegister, parse(0));
    testing.expectEqual(.CopyRegister, parse(1));
    testing.expectEqual(.AddToRegister, parse(2));
    testing.expectEqual(.AddConstantToRegister, parse(3));
    testing.expectEqual(.Call, parse(4));
    testing.expectEqual(.Return, parse(5));
    testing.expectEqual(.Yield, parse(6));
    testing.expectEqual(.Jump, parse(7));
    testing.expectEqual(.ActivateThread, parse(8));
    testing.expectEqual(.JumpIfNotZero, parse(9));
    testing.expectEqual(.ConditionalJump, parse(10));
    testing.expectEqual(.SetPalette, parse(11));
    testing.expectEqual(.ControlThreads, parse(12));
    testing.expectEqual(.SelectVideoBuffer, parse(13));
    testing.expectEqual(.FillVideoBuffer, parse(14));
    testing.expectEqual(.CopyVideoBuffer, parse(15));
    testing.expectEqual(.RenderVideoBuffer, parse(16));
    testing.expectEqual(.KillThread, parse(17));
    testing.expectEqual(.DrawString, parse(18));
    testing.expectEqual(.SubstractFromRegister, parse(19));
    testing.expectEqual(.AndRegister, parse(20));
    testing.expectEqual(.OrRegister, parse(21));
    testing.expectEqual(.ShiftRegisterLeft, parse(22));
    testing.expectEqual(.ShiftRegisterRight, parse(23));
    testing.expectEqual(.ControlSound, parse(24));
    testing.expectEqual(.ControlResources, parse(25));
    testing.expectEqual(.ControlMusic, parse(26));

    testing.expectEqual(.DrawSpritePolygon, parse(0b0100_0000));
    testing.expectEqual(.DrawSpritePolygon, parse(0b0111_1111));
    testing.expectEqual(.DrawBackgroundPolygon, parse(0b1000_0000));
    testing.expectEqual(.DrawBackgroundPolygon, parse(0b1111_1111));

    testing.expectError(error.InvalidOpcode, parse(27));
    testing.expectError(error.InvalidOpcode, parse(63));
}
