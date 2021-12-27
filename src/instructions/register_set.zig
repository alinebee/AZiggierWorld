const Opcode = @import("../values/opcode.zig");
const Register = @import("../values/register.zig");
const RegisterID = @import("../values/register_id.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");

/// Set a specific register to a constant value.
pub const Instance = struct {
    /// The ID of the register to set.
    destination: RegisterID.Raw,

    /// The constant value to set the register to.
    value: Register.Signed,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        machine.registers[self.destination] = self.value;
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 4 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) Error!Instance {
    return Instance{
        .destination = try program.read(RegisterID.Raw),
        .value = try program.read(Register.Signed),
    };
}

pub const Error = Program.Error;

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.RegisterSet);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [4]u8{ raw_opcode, 16, 0b1011_0110, 0b0010_1011 }; // -18901 in two's complement
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 4 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 4);

    try testing.expectEqual(16, instruction.destination);
    try testing.expectEqual(-18901, instruction.value);
}

test "execute updates specified register with value" {
    const instruction = Instance{
        .destination = 16,
        .value = -1234,
    };

    var machine = Machine.test_machine(null);
    defer machine.deinit();

    instruction.execute(&machine);

    try testing.expectEqual(-1234, machine.registers[16]);
}
