const Opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");

pub const Error = Program.Error;

/// Set a specific register to a constant value.
pub const Instance = struct {
    /// The ID of the register to set.
    destination: Machine.RegisterID,

    /// The constant value to set the register to.
    value: Machine.RegisterValue,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        machine.registers[self.destination] = self.value;
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 4 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    return Instance{
        .destination = try program.read(Machine.RegisterID),
        .value = try program.read(Machine.RegisterValue),
    };
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.SetRegister);

    pub const valid = [4]u8{ raw_opcode, 16, 0b1011_0110, 0b0010_1011 }; // -18901 in two's complement
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 4 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 4);

    testing.expectEqual(16, instruction.destination);
    testing.expectEqual(-18901, instruction.value);
}

test "execute updates specified register with value" {
    const instruction = Instance{
        .destination = 16,
        .value = -1234,
    };

    var machine = Machine.new();
    instruction.execute(&machine);

    testing.expectEqual(-1234, machine.registers[16]);
}
