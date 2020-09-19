const Program = @import("../machine/program.zig");
const Opcode = @import("../values/opcode.zig");
const Machine = @import("../machine/machine.zig");

const ActivateThread = @import("activate_thread.zig");
const ControlThreads = @import("control_threads.zig");
const SetRegister = @import("set_register.zig");
const CopyRegister = @import("copy_register.zig");
const ControlResources = @import("control_resources.zig");
const ControlMusic = @import("control_music.zig");
const ControlSound = @import("control_sound.zig");
const ConditionalJump = @import("conditional_jump.zig");
const DrawSpritePolygon = @import("draw_sprite_polygon.zig");
const DrawBackgroundPolygon = @import("draw_background_polygon.zig");
const DrawString = @import("draw_string.zig");

const introspection = @import("../utils/introspection.zig");

pub const Error = Opcode.Error ||
    Program.Error ||
    ActivateThread.Error ||
    ControlThreads.Error ||
    SetRegister.Error ||
    CopyRegister.Error ||
    ControlResources.Error ||
    ControlMusic.Error ||
    ControlSound.Error ||
    ConditionalJump.Error ||
    DrawSpritePolygon.Error ||
    DrawBackgroundPolygon.Error ||
    DrawString.Error ||
    error{
    /// Bytecode contained an opcode that is not yet implemented.
    UnimplementedOpcode,
};

/// A union type that wraps all possible bytecode instructions.
pub const Wrapped = union(enum) {
    // TODO: once all instructions are implemented, this union can use Opcode.Enum as its enum type.
    ActivateThread: ActivateThread.Instance,
    ControlThreads: ControlThreads.Instance,
    SetRegister: SetRegister.Instance,
    CopyRegister: CopyRegister.Instance,
    ControlResources: ControlResources.Instance,
    ControlMusic: ControlMusic.Instance,
    ControlSound: ControlSound.Instance,
    ConditionalJump: ConditionalJump.Instance,
    DrawSpritePolygon: DrawSpritePolygon.Instance,
    DrawBackgroundPolygon: DrawBackgroundPolygon.Instance,
    DrawString: DrawString.Instance,
};

/// Parse the next instruction from a bytecode program and wrap it in a Wrapped union type.
/// Returns the wrapped instruction or an error if the bytecode could not be interpreted as an instruction.
pub fn parseNextInstruction(program: *Program.Instance) Error!Wrapped {
    const raw_opcode = try program.read(Opcode.Raw);
    const opcode = try Opcode.parse(raw_opcode);

    return switch (opcode) {
        .ActivateThread => wrap("ActivateThread", ActivateThread, raw_opcode, program),
        .ControlThreads => wrap("ControlThreads", ControlThreads, raw_opcode, program),
        .SetRegister => wrap("SetRegister", SetRegister, raw_opcode, program),
        .CopyRegister => wrap("CopyRegister", CopyRegister, raw_opcode, program),
        .ControlResources => wrap("ControlResources", ControlResources, raw_opcode, program),
        .ControlMusic => wrap("ControlMusic", ControlMusic, raw_opcode, program),
        .ControlSound => wrap("ControlSound", ControlSound, raw_opcode, program),
        .ConditionalJump => wrap("ConditionalJump", ConditionalJump, raw_opcode, program),
        .DrawSpritePolygon => wrap("DrawSpritePolygon", DrawSpritePolygon, raw_opcode, program),
        .DrawBackgroundPolygon => wrap("DrawBackgroundPolygon", DrawBackgroundPolygon, raw_opcode, program),
        .DrawString => wrap("DrawString", DrawString, raw_opcode, program),
        else => error.UnimplementedOpcode,
    };
}

/// Parse an instruction of the specified type from the program,
/// and wrap it in a Wrapped union type initialized to the appropriate field.
fn wrap(comptime field_name: []const u8, comptime Instruction: type, raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Wrapped {
    return @unionInit(Wrapped, field_name, try Instruction.parse(raw_opcode, program));
}

/// Parse and execute the next instruction from a bytecode program on the specified virtual machine.
pub fn executeNextInstruction(program: *Program.Instance, machine: *Machine.Instance) Error!void {
    const raw_opcode = try program.read(Opcode.Raw);
    const opcode = try Opcode.parse(raw_opcode);

    try switch (opcode) {
        .ActivateThread => execute(ActivateThread, raw_opcode, program, machine),
        .ControlThreads => execute(ControlThreads, raw_opcode, program, machine),
        .SetRegister => execute(SetRegister, raw_opcode, program, machine),
        .CopyRegister => execute(CopyRegister, raw_opcode, program, machine),
        .ControlResources => execute(ControlResources, raw_opcode, program, machine),
        .ControlMusic => execute(ControlMusic, raw_opcode, program, machine),
        .ControlSound => execute(ControlSound, raw_opcode, program, machine),
        .ConditionalJump => execute(ConditionalJump, raw_opcode, program, machine),
        .DrawSpritePolygon => execute(DrawSpritePolygon, raw_opcode, program, machine),
        .DrawBackgroundPolygon => execute(DrawBackgroundPolygon, raw_opcode, program, machine),
        .DrawString => execute(DrawString, raw_opcode, program, machine),
        else => error.UnimplementedOpcode,
    };
}

fn execute(comptime Instruction: type, raw_opcode: Opcode.Raw, program: *Program.Instance, machine: *Machine.Instance) Error!void {
    const instruction = try Instruction.parse(raw_opcode, program);
    const ReturnType = introspection.returnType(instruction.execute);

    // You'd think there'd be an easier way to express "try the function if necessary, otherwise just call it".
    if (@typeInfo(ReturnType) == .ErrorUnion) {
        try instruction.execute(machine);
    } else {
        instruction.execute(machine);
    }
}

// -- Test helpers --

/// Try to parse a literal sequence of bytecode into an Instruction union value.
fn expectParse(bytecode: []const u8) !Wrapped {
    var program = Program.new(bytecode);
    return try parseNextInstruction(&program);
}

/// Assert that a wrapped instruction previously generated by `parse` matches the expected union type.
/// (expectEqual won't coerce tagged unions to their underlying enum type, preventing easy comparison.)
fn expectWrappedType(expected: @TagType(Wrapped), actual: @TagType(Wrapped)) void {
    testing.expectEqual(expected, actual);
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parseNextInstruction returns ActivateThread instruction when given valid bytecode" {
    const instruction = try expectParse(&ActivateThread.BytecodeExamples.valid);
    expectWrappedType(.ActivateThread, instruction);
}

test "parseNextInstruction returns ControlThreads instruction when given valid bytecode" {
    const instruction = try expectParse(&ControlThreads.BytecodeExamples.valid);
    expectWrappedType(.ControlThreads, instruction);
}

test "parseNextInstruction returns SetRegister instruction when given valid bytecode" {
    const instruction = try expectParse(&SetRegister.BytecodeExamples.valid);
    expectWrappedType(.SetRegister, instruction);
}

test "parseNextInstruction returns CopyRegister instruction when given valid bytecode" {
    const instruction = try expectParse(&CopyRegister.BytecodeExamples.valid);
    expectWrappedType(.CopyRegister, instruction);
}

test "parseNextInstruction returns ControlResources instruction when given valid bytecode" {
    const instruction = try expectParse(&ControlResources.BytecodeExamples.unload_all);
    expectWrappedType(.ControlResources, instruction);
}

test "parseNextInstruction returns ControlMusic instruction when given valid bytecode" {
    const instruction = try expectParse(&ControlMusic.BytecodeExamples.play);
    expectWrappedType(.ControlMusic, instruction);
}

test "parseNextInstruction returns ControlSound instruction when given valid bytecode" {
    const instruction = try expectParse(&ControlSound.BytecodeExamples.play);
    expectWrappedType(.ControlSound, instruction);
}

test "parseNextInstruction returns ConditionalJump instruction when given valid bytecode" {
    const instruction = try expectParse(&ConditionalJump.BytecodeExamples.equal_to_register);
    expectWrappedType(.ConditionalJump, instruction);
}

test "parseNextInstruction returns DrawSpriteolygon instruction when given valid bytecode" {
    const instruction = try expectParse(&DrawSpritePolygon.BytecodeExamples.registers);
    expectWrappedType(.DrawSpritePolygon, instruction);
}

test "parseNextInstruction returns DrawBackgroundPolygon instruction when given valid bytecode" {
    const instruction = try expectParse(&DrawBackgroundPolygon.BytecodeExamples.low_x);
    expectWrappedType(.DrawBackgroundPolygon, instruction);
}

test "parseNextInstruction returns DrawString instruction when given valid bytecode" {
    const instruction = try expectParse(&DrawString.BytecodeExamples.valid);
    expectWrappedType(.DrawString, instruction);
}

test "parseNextInstruction returns error.InvalidOpcode error when it encounters an unknown opcode" {
    const bytecode = [_]u8{63}; // Not a valid opcode
    testing.expectError(error.InvalidOpcode, expectParse(&bytecode));
}

test "parseNextInstruction returns error.UnimplementedOpcode error when it encounters a not-yet-implemented opcode" {
    const bytecode = [_]u8{@enumToInt(Opcode.Enum.Yield)};
    testing.expectError(error.UnimplementedOpcode, expectParse(&bytecode));
}

test "executeNextInstruction executes arbitrary instruction on machine when given valid bytecode" {
    var program = Program.new(&SetRegister.BytecodeExamples.valid);
    var machine = Machine.new();

    try executeNextInstruction(&program, &machine);

    testing.expectEqual(-18901, machine.registers[16]);
}
