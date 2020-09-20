const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const RegisterID = @import("../values/register_id.zig");

/// Add the value from one register to another, wrapping on overflow.
pub const Instance = struct {
    /// The ID of the register to add to.
    destination: RegisterID.Raw,

    /// The ID of the register containing the value to add.
    source: RegisterID.Raw,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        machine.registers[self.destination] +%= machine.registers[self.source];
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 3 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    return Instance{
        .destination = try program.read(RegisterID.Raw),
        .source = try program.read(RegisterID.Raw),
    };
}

pub const Error = Program.Error;

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.RegisterAdd);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [3]u8{ raw_opcode, 16, 17 };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 3);

    testing.expectEqual(16, instruction.destination);
    testing.expectEqual(17, instruction.source);
}

test "execute adds to destination register and leaves source register alone" {
    const instruction = Instance{
        .destination = 16,
        .source = 17,
    };

    var machine = Machine.new();
    machine.registers[16] = 125;
    machine.registers[17] = -50;

    instruction.execute(&machine);

    testing.expectEqual(75, machine.registers[16]);
    testing.expectEqual(-50, machine.registers[17]);
}

test "execute wraps on overflow" {
    const instruction = Instance{
        .destination = 16,
        .source = 17,
    };

    var machine = Machine.new();
    machine.registers[16] = 32767;
    machine.registers[17] = 1;

    instruction.execute(&machine);

    testing.expectEqual(-32768, machine.registers[16]);
}

test "execute wraps on underflow" {
    const instruction = Instance{
        .destination = 16,
        .source = 17,
    };

    var machine = Machine.new();
    machine.registers[16] = -32768;
    machine.registers[17] = -1;

    instruction.execute(&machine);

    testing.expectEqual(32767, machine.registers[16]);
}
