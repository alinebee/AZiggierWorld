const anotherworld = @import("../anotherworld.zig");

const Opcode = @import("opcode.zig").Opcode;
const Program = @import("program.zig").Program;

/// A union that represents the set of all possible bytecode instructions, indexed by opcode.
/// This wrapped type is intended for introspection and reverse engineering of Another World
/// bytecode programs, and is not used directly in the emulator; during normal emulator flow,
/// individual instructions are executed immediately after being parsed to avoid switching twice.
pub const Instruction = union(Opcode) {
    ActivateThread: ActivateThread,
    Call: Call,
    ControlMusic: ControlMusic,
    ControlResources: ControlResources,
    ControlSound: ControlSound,
    ControlThreads: ControlThreads,
    CopyVideoBuffer: CopyVideoBuffer,
    DrawBackgroundPolygon: DrawBackgroundPolygon,
    DrawSpritePolygon: DrawSpritePolygon,
    DrawString: DrawString,
    FillVideoBuffer: FillVideoBuffer,
    Jump: Jump,
    JumpConditional: JumpConditional,
    JumpIfNotZero: JumpIfNotZero,
    Kill: Kill,
    RegisterAdd: RegisterAdd,
    RegisterAddConstant: RegisterAddConstant,
    RegisterAnd: RegisterAnd,
    RegisterCopy: RegisterCopy,
    RegisterOr: RegisterOr,
    RegisterSet: RegisterSet,
    RegisterShiftLeft: RegisterShiftLeft,
    RegisterShiftRight: RegisterShiftRight,
    RegisterSubtract: RegisterSubtract,
    RenderVideoBuffer: RenderVideoBuffer,
    Return: Return,
    SelectPalette: SelectPalette,
    SelectVideoBuffer: SelectVideoBuffer,
    Yield: Yield,

    pub const ActivateThread = @import("instructions/activate_thread.zig").ActivateThread;
    pub const Call = @import("instructions/call.zig").Call;
    pub const ControlMusic = @import("instructions/control_music.zig").ControlMusic;
    pub const ControlResources = @import("instructions/control_resources.zig").ControlResources;
    pub const ControlSound = @import("instructions/control_sound.zig").ControlSound;
    pub const ControlThreads = @import("instructions/control_threads.zig").ControlThreads;
    pub const CopyVideoBuffer = @import("instructions/copy_video_buffer.zig").CopyVideoBuffer;
    pub const DrawBackgroundPolygon = @import("instructions/draw_background_polygon.zig").DrawBackgroundPolygon;
    pub const DrawSpritePolygon = @import("instructions/draw_sprite_polygon.zig").DrawSpritePolygon;
    pub const DrawString = @import("instructions/draw_string.zig").DrawString;
    pub const FillVideoBuffer = @import("instructions/fill_video_buffer.zig").FillVideoBuffer;
    pub const Jump = @import("instructions/jump.zig").Jump;
    pub const JumpConditional = @import("instructions/jump_conditional.zig").JumpConditional;
    pub const JumpIfNotZero = @import("instructions/jump_if_not_zero.zig").JumpIfNotZero;
    pub const Kill = @import("instructions/kill.zig").Kill;
    pub const RegisterAdd = @import("instructions/register_add.zig").RegisterAdd;
    pub const RegisterAddConstant = @import("instructions/register_add_constant.zig").RegisterAddConstant;
    pub const RegisterAnd = @import("instructions/register_and.zig").RegisterAnd;
    pub const RegisterCopy = @import("instructions/register_copy.zig").RegisterCopy;
    pub const RegisterOr = @import("instructions/register_or.zig").RegisterOr;
    pub const RegisterSet = @import("instructions/register_set.zig").RegisterSet;
    pub const RegisterShiftLeft = @import("instructions/register_shift_left.zig").RegisterShiftLeft;
    pub const RegisterShiftRight = @import("instructions/register_shift_right.zig").RegisterShiftRight;
    pub const RegisterSubtract = @import("instructions/register_subtract.zig").RegisterSubtract;
    pub const RenderVideoBuffer = @import("instructions/render_video_buffer.zig").RenderVideoBuffer;
    pub const Return = @import("instructions/return.zig").Return;
    pub const SelectPalette = @import("instructions/select_palette.zig").SelectPalette;
    pub const SelectVideoBuffer = @import("instructions/select_video_buffer.zig").SelectVideoBuffer;
    pub const Yield = @import("instructions/yield.zig").Yield;

    /// Parse the next instruction from a bytecode program and wrap it in an Instruction union type.
    /// Returns the instruction or an error if the program could not be read or the bytecode
    /// could not be interpreted as an instruction.
    pub fn parse(program: *Program) !Instruction {
        const raw_opcode = try program.read(Opcode.Raw);
        const opcode = try Opcode.parse(raw_opcode);

        return switch (opcode) {
            .ActivateThread => parseSpecific(ActivateThread, raw_opcode, program),
            .Call => parseSpecific(Call, raw_opcode, program),
            .ControlMusic => parseSpecific(ControlMusic, raw_opcode, program),
            .ControlResources => parseSpecific(ControlResources, raw_opcode, program),
            .ControlSound => parseSpecific(ControlSound, raw_opcode, program),
            .ControlThreads => parseSpecific(ControlThreads, raw_opcode, program),
            .CopyVideoBuffer => parseSpecific(CopyVideoBuffer, raw_opcode, program),
            .DrawBackgroundPolygon => parseSpecific(DrawBackgroundPolygon, raw_opcode, program),
            .DrawSpritePolygon => parseSpecific(DrawSpritePolygon, raw_opcode, program),
            .DrawString => parseSpecific(DrawString, raw_opcode, program),
            .FillVideoBuffer => parseSpecific(FillVideoBuffer, raw_opcode, program),
            .Jump => parseSpecific(Jump, raw_opcode, program),
            .JumpConditional => parseSpecific(JumpConditional, raw_opcode, program),
            .JumpIfNotZero => parseSpecific(JumpIfNotZero, raw_opcode, program),
            .Kill => parseSpecific(Kill, raw_opcode, program),
            .RegisterAdd => parseSpecific(RegisterAdd, raw_opcode, program),
            .RegisterAddConstant => parseSpecific(RegisterAddConstant, raw_opcode, program),
            .RegisterAnd => parseSpecific(RegisterAnd, raw_opcode, program),
            .RegisterCopy => parseSpecific(RegisterCopy, raw_opcode, program),
            .RegisterOr => parseSpecific(RegisterOr, raw_opcode, program),
            .RegisterSet => parseSpecific(RegisterSet, raw_opcode, program),
            .RegisterShiftLeft => parseSpecific(RegisterShiftLeft, raw_opcode, program),
            .RegisterShiftRight => parseSpecific(RegisterShiftRight, raw_opcode, program),
            .RegisterSubtract => parseSpecific(RegisterSubtract, raw_opcode, program),
            .RenderVideoBuffer => parseSpecific(RenderVideoBuffer, raw_opcode, program),
            .Return => parseSpecific(Return, raw_opcode, program),
            .SelectPalette => parseSpecific(SelectPalette, raw_opcode, program),
            .SelectVideoBuffer => parseSpecific(SelectVideoBuffer, raw_opcode, program),
            .Yield => parseSpecific(Yield, raw_opcode, program),
        };
    }

    /// Parse an instruction of the specified type from the program,
    /// and wrap it in an Instruction union type initialized to the appropriate field.
    fn parseSpecific(comptime SpecificInstruction: type, raw_opcode: Opcode.Raw, program: *Program) !Instruction {
        const field_name = @tagName(SpecificInstruction.opcode);
        return @unionInit(Instruction, field_name, try SpecificInstruction.parse(raw_opcode, program));
    }
};

// -- Test helpers --

/// Try to parse a literal sequence of bytecode into an Instruction union value.
fn expectParse(program_data: []const u8) !Instruction {
    var program = try Program.init(program_data);
    return try Instruction.parse(&program);
}

// -- Tests --

const testing = @import("utils").testing;

// - Instruction.parse tests --

test "Instruction.parse returns expected instruction type when given valid bytecode" {
    try testing.expectEqualTags(.ActivateThread, try expectParse(&Instruction.ActivateThread.Fixtures.valid));
    try testing.expectEqualTags(.Call, try expectParse(&Instruction.Call.Fixtures.valid));
    try testing.expectEqualTags(.ControlMusic, try expectParse(&Instruction.ControlMusic.Fixtures.valid));
    try testing.expectEqualTags(.ControlResources, try expectParse(&Instruction.ControlResources.Fixtures.valid));
    try testing.expectEqualTags(.ControlSound, try expectParse(&Instruction.ControlSound.Fixtures.valid));
    try testing.expectEqualTags(.ControlThreads, try expectParse(&Instruction.ControlThreads.Fixtures.valid));
    try testing.expectEqualTags(.DrawBackgroundPolygon, try expectParse(&Instruction.DrawBackgroundPolygon.Fixtures.valid));
    try testing.expectEqualTags(.DrawSpritePolygon, try expectParse(&Instruction.DrawSpritePolygon.Fixtures.valid));
    try testing.expectEqualTags(.DrawString, try expectParse(&Instruction.DrawString.Fixtures.valid));
    try testing.expectEqualTags(.FillVideoBuffer, try expectParse(&Instruction.FillVideoBuffer.Fixtures.valid));
    try testing.expectEqualTags(.Jump, try expectParse(&Instruction.Jump.Fixtures.valid));
    try testing.expectEqualTags(.JumpConditional, try expectParse(&Instruction.JumpConditional.Fixtures.valid));
    try testing.expectEqualTags(.JumpIfNotZero, try expectParse(&Instruction.JumpIfNotZero.Fixtures.valid));
    try testing.expectEqualTags(.Kill, try expectParse(&Instruction.Kill.Fixtures.valid));
    try testing.expectEqualTags(.RegisterAdd, try expectParse(&Instruction.RegisterAdd.Fixtures.valid));
    try testing.expectEqualTags(.RegisterAddConstant, try expectParse(&Instruction.RegisterAddConstant.Fixtures.valid));
    try testing.expectEqualTags(.RegisterAnd, try expectParse(&Instruction.RegisterAnd.Fixtures.valid));
    try testing.expectEqualTags(.RegisterCopy, try expectParse(&Instruction.RegisterCopy.Fixtures.valid));
    try testing.expectEqualTags(.RegisterOr, try expectParse(&Instruction.RegisterOr.Fixtures.valid));
    try testing.expectEqualTags(.RegisterSet, try expectParse(&Instruction.RegisterSet.Fixtures.valid));
    try testing.expectEqualTags(.RegisterShiftLeft, try expectParse(&Instruction.RegisterShiftLeft.Fixtures.valid));
    try testing.expectEqualTags(.RegisterSubtract, try expectParse(&Instruction.RegisterSubtract.Fixtures.valid));
    try testing.expectEqualTags(.RenderVideoBuffer, try expectParse(&Instruction.RenderVideoBuffer.Fixtures.valid));
    try testing.expectEqualTags(.Return, try expectParse(&Instruction.Return.Fixtures.valid));
    try testing.expectEqualTags(.SelectPalette, try expectParse(&Instruction.SelectPalette.Fixtures.valid));
    try testing.expectEqualTags(.SelectVideoBuffer, try expectParse(&Instruction.SelectVideoBuffer.Fixtures.valid));
    try testing.expectEqualTags(.Yield, try expectParse(&Instruction.Yield.Fixtures.valid));
}

test "Instruction.parse returns error.InvalidOpcode error when it encounters an unknown opcode" {
    const program_data = [_]u8{63}; // Not a valid opcode
    try testing.expectError(error.InvalidOpcode, expectParse(&program_data));
}
