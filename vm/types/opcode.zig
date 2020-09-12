//! Types and operations dealing with built-in opcodes in Another World bytecode.
//! See instruction.zig for how these are mapped to implementations of those opcodes.

/// A raw opcode as represented in Another World's bytecode.
pub const Raw = u8;

/// The known opcodes used in Another World's bytecode.
/// These map to individual instruction types, each defined in their own zig file with the same name.
/// See https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter for a list of opccodes
/// (whose names do not match the ones I have chosen here).
pub const Enum = enum (Raw) {
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

    // Beyond these simple enums there are two higher opcodes marked by bits 6 and 7 of the opcode,
    // which reuse the lower bits of the opcode to store additional parameters to the instruction.
    _,
};

pub fn parse(raw_opcode: Raw) Enum {
    return @intToEnum(Enum, raw_opcode);
}
