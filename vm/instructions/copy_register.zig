const Opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");

pub const Error = Program.Error;

/// Copy the value of one register to another.
pub const Instance = struct {
    /// The ID of the register to copy into.
    destination: Machine.RegisterID,

    /// The ID of the register to copy from.
    source: Machine.RegisterID,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        machine.registers[self.destination] = machine.registers[self.source];
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 2 bytes from the bytecode on success.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    return Instance{
        .destination = try program.read(Machine.RegisterID),
        .source = try program.read(Machine.RegisterID),
    };
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.CopyRegister);

    pub const valid = [_]u8{ raw_opcode, 16, 17 };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const debugParseInstruction = @import("test_helpers.zig").debugParseInstruction;

test "parse parses valid bytecode and consumes 2 bytes" {
    const instruction = try debugParseInstruction(parse, &BytecodeExamples.valid, 2);

    testing.expectEqual(16, instruction.destination);
    testing.expectEqual(17, instruction.source);
}

test "parse fails to parse incomplete bytecode and consumes all available bytes" {
    testing.expectError(
        error.EndOfProgram,
        debugParseInstruction(parse, BytecodeExamples.valid[0..2], 1),
    );
}

test "execute updates specified register with value" {
    const instruction = Instance{
        .destination = 16,
        .source = 17,
    };

    var machine = Machine.new();
    machine.registers[17] = -900;

    instruction.execute(&machine);

    testing.expectEqual(-900, machine.registers[16]);
    testing.expectEqual(-900, machine.registers[17]);
}
