//! This file defines functions to parse and execute the instructions in Another World's bytecode programs.
//! Each instruction is modelled as its own separate Zig type; the functions in this file parse raw bytes
//! into the appropriate instruction type (and then execute it).
//!
//! Right now this file feels like a mess; there is a lot of copypasta that could probably
//! be cleaned up with some Zig compile-time code generation.

const Program = @import("../machine/program.zig");
const Opcode = @import("../values/opcode.zig");
const Machine = @import("../machine/machine.zig");
const Action = @import("action.zig");

const ActivateThread = @import("activate_thread.zig");
const Call = @import("call.zig");
const ControlMusic = @import("control_music.zig");
const ControlResources = @import("control_resources.zig");
const ControlSound = @import("control_sound.zig");
const ControlThreads = @import("control_threads.zig");
const CopyVideoBuffer = @import("copy_video_buffer.zig");
const DrawBackgroundPolygon = @import("draw_background_polygon.zig");
const DrawSpritePolygon = @import("draw_sprite_polygon.zig");
const DrawString = @import("draw_string.zig");
const FillVideoBuffer = @import("fill_video_buffer.zig");
const Jump = @import("jump.zig");
const JumpConditional = @import("jump_conditional.zig");
const JumpIfNotZero = @import("jump_if_not_zero.zig");
const Kill = @import("kill.zig");
const RegisterAdd = @import("register_add.zig");
const RegisterAddConstant = @import("register_add_constant.zig");
const RegisterAnd = @import("register_and.zig");
const RegisterCopy = @import("register_copy.zig");
const RegisterOr = @import("register_or.zig");
const RegisterSet = @import("register_set.zig");
const RegisterShiftLeft = @import("register_shift_left.zig");
const RegisterShiftRight = @import("register_shift_right.zig");
const RegisterSubtract = @import("register_subtract.zig");
const RenderVideoBuffer = @import("render_video_buffer.zig");
const Return = @import("return.zig");
const SelectPalette = @import("select_palette.zig");
const SelectVideoBuffer = @import("select_video_buffer.zig");
const Yield = @import("yield.zig");

const introspection = @import("../utils/introspection.zig");

/// Parse and execute the next instruction from a bytecode program on the specified virtual machine.
/// Returns an enum indicating whether execution should continue or stop as a result of that instruction.
/// Returns an error if the bytecode could not be interpreted as an instruction.
pub fn executeNextInstruction(program: *Program.Instance, machine: *Machine.Instance) !Action.Enum {
    const raw_opcode = try program.read(Opcode.Raw);
    const opcode = try Opcode.parse(raw_opcode);

    return switch (opcode) {
        .ActivateThread => execute(ActivateThread, raw_opcode, program, machine),
        .Call => execute(Call, raw_opcode, program, machine),
        .ControlMusic => execute(ControlMusic, raw_opcode, program, machine),
        .ControlResources => execute(ControlResources, raw_opcode, program, machine),
        .ControlSound => execute(ControlSound, raw_opcode, program, machine),
        .ControlThreads => execute(ControlThreads, raw_opcode, program, machine),
        .CopyVideoBuffer => execute(CopyVideoBuffer, raw_opcode, program, machine),
        .DrawBackgroundPolygon => execute(DrawBackgroundPolygon, raw_opcode, program, machine),
        .DrawSpritePolygon => execute(DrawSpritePolygon, raw_opcode, program, machine),
        .DrawString => execute(DrawString, raw_opcode, program, machine),
        .FillVideoBuffer => execute(FillVideoBuffer, raw_opcode, program, machine),
        .Jump => execute(Jump, raw_opcode, program, machine),
        .JumpConditional => execute(JumpConditional, raw_opcode, program, machine),
        .JumpIfNotZero => execute(JumpIfNotZero, raw_opcode, program, machine),
        .Kill => execute(Kill, raw_opcode, program, machine),
        .RegisterAdd => execute(RegisterAdd, raw_opcode, program, machine),
        .RegisterAddConstant => execute(RegisterAddConstant, raw_opcode, program, machine),
        .RegisterAnd => execute(RegisterAnd, raw_opcode, program, machine),
        .RegisterCopy => execute(RegisterCopy, raw_opcode, program, machine),
        .RegisterOr => execute(RegisterOr, raw_opcode, program, machine),
        .RegisterSet => execute(RegisterSet, raw_opcode, program, machine),
        .RegisterShiftLeft => execute(RegisterShiftLeft, raw_opcode, program, machine),
        .RegisterShiftRight => execute(RegisterShiftRight, raw_opcode, program, machine),
        .RegisterSubtract => execute(RegisterSubtract, raw_opcode, program, machine),
        .RenderVideoBuffer => execute(RenderVideoBuffer, raw_opcode, program, machine),
        .Return => execute(Return, raw_opcode, program, machine),
        .SelectPalette => execute(SelectPalette, raw_opcode, program, machine),
        .SelectVideoBuffer => execute(SelectVideoBuffer, raw_opcode, program, machine),
        .Yield => execute(Yield, raw_opcode, program, machine),
    };
}

fn execute(comptime Instruction: type, raw_opcode: Opcode.Raw, program: *Program.Instance, machine: *Machine.Instance) !Action.Enum {
    const instruction = try Instruction.parse(raw_opcode, program);

    // Zig 0.8.0 does not have a way to express "try this function if it returns an error set,
    // otherwise call it normally", hence we must check the return type at compile time and branch.
    const ReturnType = introspection.ReturnType(instruction.execute);
    const returns_error = @typeInfo(ReturnType) == .ErrorUnion;
    const result = if (returns_error)
        try instruction.execute(machine)
    else
        instruction.execute(machine);

    // Check whether this instruction returned a specific action to take after executing.
    // Most instructions just return void - assume their action will be .Continue.
    const returns_action = @TypeOf(result) == Action.Enum;
    if (returns_action) {
        return result;
    } else {
        return .Continue;
    }
}

/// A union that represents the set of all possible bytecode instructions, indexed by opcode.
/// This wrapped type is intended for introspection and reverse engineering of Another World
/// bytecode programs, and is not used directly in the emulator; during normal emulator flow,
/// individual instructions are executed immediately after being parsed.
pub const Wrapped = union(Opcode.Enum) {
    ActivateThread: ActivateThread.Instance,
    Call: Call.Instance,
    ControlMusic: ControlMusic.Instance,
    ControlResources: ControlResources.Instance,
    ControlSound: ControlSound.Instance,
    ControlThreads: ControlThreads.Instance,
    CopyVideoBuffer: CopyVideoBuffer.Instance,
    DrawBackgroundPolygon: DrawBackgroundPolygon.Instance,
    DrawSpritePolygon: DrawSpritePolygon.Instance,
    DrawString: DrawString.Instance,
    FillVideoBuffer: FillVideoBuffer.Instance,
    Jump: Jump.Instance,
    JumpConditional: JumpConditional.Instance,
    JumpIfNotZero: JumpIfNotZero.Instance,
    Kill: Kill.Instance,
    RegisterAdd: RegisterAdd.Instance,
    RegisterAddConstant: RegisterAddConstant.Instance,
    RegisterAnd: RegisterAnd.Instance,
    RegisterCopy: RegisterCopy.Instance,
    RegisterOr: RegisterOr.Instance,
    RegisterSet: RegisterSet.Instance,
    RegisterShiftLeft: RegisterShiftLeft.Instance,
    RegisterShiftRight: RegisterShiftRight.Instance,
    RegisterSubtract: RegisterSubtract.Instance,
    RenderVideoBuffer: RenderVideoBuffer.Instance,
    Return: Return.Instance,
    SelectPalette: SelectPalette.Instance,
    SelectVideoBuffer: SelectVideoBuffer.Instance,
    Yield: Yield.Instance,
};

/// Parse the next instruction from a bytecode program and wrap it in a Wrapped union type.
/// Returns the wrapped instruction or an error if the bytecode could not be interpreted as an instruction.
pub fn parseNextInstruction(program: *Program.Instance) !Wrapped {
    const raw_opcode = try program.read(Opcode.Raw);
    const opcode = try Opcode.parse(raw_opcode);

    return switch (opcode) {
        .ActivateThread => wrap("ActivateThread", ActivateThread, raw_opcode, program),
        .Call => wrap("Call", Call, raw_opcode, program),
        .ControlMusic => wrap("ControlMusic", ControlMusic, raw_opcode, program),
        .ControlResources => wrap("ControlResources", ControlResources, raw_opcode, program),
        .ControlSound => wrap("ControlSound", ControlSound, raw_opcode, program),
        .ControlThreads => wrap("ControlThreads", ControlThreads, raw_opcode, program),
        .CopyVideoBuffer => wrap("CopyVideoBuffer", CopyVideoBuffer, raw_opcode, program),
        .DrawBackgroundPolygon => wrap("DrawBackgroundPolygon", DrawBackgroundPolygon, raw_opcode, program),
        .DrawSpritePolygon => wrap("DrawSpritePolygon", DrawSpritePolygon, raw_opcode, program),
        .DrawString => wrap("DrawString", DrawString, raw_opcode, program),
        .FillVideoBuffer => wrap("FillVideoBuffer", FillVideoBuffer, raw_opcode, program),
        .Jump => wrap("Jump", Jump, raw_opcode, program),
        .JumpConditional => wrap("JumpConditional", JumpConditional, raw_opcode, program),
        .JumpIfNotZero => wrap("JumpIfNotZero", JumpIfNotZero, raw_opcode, program),
        .Kill => wrap("Kill", Kill, raw_opcode, program),
        .RegisterAdd => wrap("RegisterAdd", RegisterAdd, raw_opcode, program),
        .RegisterAddConstant => wrap("RegisterAddConstant", RegisterAddConstant, raw_opcode, program),
        .RegisterAnd => wrap("RegisterAnd", RegisterAnd, raw_opcode, program),
        .RegisterCopy => wrap("RegisterCopy", RegisterCopy, raw_opcode, program),
        .RegisterOr => wrap("RegisterOr", RegisterOr, raw_opcode, program),
        .RegisterSet => wrap("RegisterSet", RegisterSet, raw_opcode, program),
        .RegisterShiftLeft => wrap("RegisterShiftLeft", RegisterShiftLeft, raw_opcode, program),
        .RegisterShiftRight => wrap("RegisterShiftRight", RegisterShiftRight, raw_opcode, program),
        .RegisterSubtract => wrap("RegisterSubtract", RegisterSubtract, raw_opcode, program),
        .RenderVideoBuffer => wrap("RenderVideoBuffer", RenderVideoBuffer, raw_opcode, program),
        .Return => wrap("Return", Return, raw_opcode, program),
        .SelectPalette => wrap("SelectPalette", SelectPalette, raw_opcode, program),
        .SelectVideoBuffer => wrap("SelectVideoBuffer", SelectVideoBuffer, raw_opcode, program),
        .Yield => wrap("Yield", Yield, raw_opcode, program),
    };
}

/// Parse an instruction of the specified type from the program,
/// and wrap it in a Wrapped union type initialized to the appropriate field.
fn wrap(comptime field_name: []const u8, comptime Instruction: type, raw_opcode: Opcode.Raw, program: *Program.Instance) !Wrapped {
    return @unionInit(Wrapped, field_name, try Instruction.parse(raw_opcode, program));
}

// -- Test helpers --

/// Try to parse a literal sequence of bytecode into an Instruction union value.
fn expectParse(bytecode: []const u8) !Wrapped {
    var program = Program.new(bytecode);
    return try parseNextInstruction(&program);
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parseNextInstruction returns expected instruction type when given valid bytecode" {
    try testing.expectEqualTags(.ActivateThread, try expectParse(&ActivateThread.BytecodeExamples.valid));
    try testing.expectEqualTags(.Call, try expectParse(&Call.BytecodeExamples.valid));
    try testing.expectEqualTags(.ControlMusic, try expectParse(&ControlMusic.BytecodeExamples.valid));
    try testing.expectEqualTags(.ControlResources, try expectParse(&ControlResources.BytecodeExamples.valid));
    try testing.expectEqualTags(.ControlSound, try expectParse(&ControlSound.BytecodeExamples.valid));
    try testing.expectEqualTags(.ControlThreads, try expectParse(&ControlThreads.BytecodeExamples.valid));
    try testing.expectEqualTags(.DrawBackgroundPolygon, try expectParse(&DrawBackgroundPolygon.BytecodeExamples.valid));
    try testing.expectEqualTags(.DrawSpritePolygon, try expectParse(&DrawSpritePolygon.BytecodeExamples.valid));
    try testing.expectEqualTags(.DrawString, try expectParse(&DrawString.BytecodeExamples.valid));
    try testing.expectEqualTags(.FillVideoBuffer, try expectParse(&FillVideoBuffer.BytecodeExamples.valid));
    try testing.expectEqualTags(.Jump, try expectParse(&Jump.BytecodeExamples.valid));
    try testing.expectEqualTags(.JumpConditional, try expectParse(&JumpConditional.BytecodeExamples.valid));
    try testing.expectEqualTags(.JumpIfNotZero, try expectParse(&JumpIfNotZero.BytecodeExamples.valid));
    try testing.expectEqualTags(.Kill, try expectParse(&Kill.BytecodeExamples.valid));
    try testing.expectEqualTags(.RegisterAdd, try expectParse(&RegisterAdd.BytecodeExamples.valid));
    try testing.expectEqualTags(.RegisterAddConstant, try expectParse(&RegisterAddConstant.BytecodeExamples.valid));
    try testing.expectEqualTags(.RegisterAnd, try expectParse(&RegisterAnd.BytecodeExamples.valid));
    try testing.expectEqualTags(.RegisterCopy, try expectParse(&RegisterCopy.BytecodeExamples.valid));
    try testing.expectEqualTags(.RegisterOr, try expectParse(&RegisterOr.BytecodeExamples.valid));
    try testing.expectEqualTags(.RegisterSet, try expectParse(&RegisterSet.BytecodeExamples.valid));
    try testing.expectEqualTags(.RegisterShiftLeft, try expectParse(&RegisterShiftLeft.BytecodeExamples.valid));
    try testing.expectEqualTags(.RegisterSubtract, try expectParse(&RegisterSubtract.BytecodeExamples.valid));
    try testing.expectEqualTags(.RenderVideoBuffer, try expectParse(&RenderVideoBuffer.BytecodeExamples.valid));
    try testing.expectEqualTags(.Return, try expectParse(&Return.BytecodeExamples.valid));
    try testing.expectEqualTags(.SelectPalette, try expectParse(&SelectPalette.BytecodeExamples.valid));
    try testing.expectEqualTags(.SelectVideoBuffer, try expectParse(&SelectVideoBuffer.BytecodeExamples.valid));
    try testing.expectEqualTags(.Yield, try expectParse(&Yield.BytecodeExamples.valid));
}

test "parseNextInstruction returns error.InvalidOpcode error when it encounters an unknown opcode" {
    const bytecode = [_]u8{63}; // Not a valid opcode
    try testing.expectError(error.InvalidOpcode, expectParse(&bytecode));
}

test "executeNextInstruction executes arbitrary instruction on machine when given valid bytecode" {
    var machine = Machine.test_machine(&RegisterSet.BytecodeExamples.valid);
    defer machine.deinit();

    const action = try executeNextInstruction(&machine.program, &machine);

    try testing.expectEqual(.Continue, action);
    try testing.expectEqual(-18901, machine.registers[16]);
}

test "executeNextInstruction returns DeactivateThread action if specified" {
    var machine = Machine.test_machine(&Kill.BytecodeExamples.valid);
    defer machine.deinit();

    const action = try executeNextInstruction(&machine.program, &machine);

    try testing.expectEqual(.DeactivateThread, action);
}

test "executeNextInstruction returns YieldToNextThread action if specified" {
    var machine = Machine.test_machine(&Yield.BytecodeExamples.valid);
    defer machine.deinit();

    const action = try executeNextInstruction(&machine.program, &machine);

    try testing.expectEqual(.YieldToNextThread, action);
}
