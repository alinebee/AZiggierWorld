const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const RegisterID = @import("../values/register_id.zig");

/// Subtract the value in one register from another, wrapping on overflow.
pub const Instance = struct {
    /// The ID of the register to subtract from.
    destination: RegisterID.Raw,

    /// The ID of the register containing the value to subtract.
    source: RegisterID.Raw,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        // Zig syntax: -% wraps on overflow, whereas - traps.
        machine.registers[self.destination] -%= machine.registers[self.source];
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 3 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) Error!Instance {
    return Instance{
        .destination = try program.read(RegisterID.Raw),
        .source = try program.read(RegisterID.Raw),
    };
}

pub const Error = Program.Error;

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.RegisterSubtract);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [3]u8{ raw_opcode, 16, 17 };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 3);

    try testing.expectEqual(16, instruction.destination);
    try testing.expectEqual(17, instruction.source);
}

test "execute subtracts from destination register and leaves source register alone" {
    const instruction = Instance{
        .destination = 16,
        .source = 17,
    };

    var machine = Machine.new();
    machine.registers[16] = 125;
    machine.registers[17] = 50;

    instruction.execute(&machine);

    try testing.expectEqual(75, machine.registers[16]);
    try testing.expectEqual(50, machine.registers[17]);
}

test "execute wraps on overflow" {
    const instruction = Instance{
        .destination = 16,
        .source = 17,
    };

    var machine = Machine.new();
    machine.registers[16] = 32767;
    machine.registers[17] = -1;

    instruction.execute(&machine);

    try testing.expectEqual(-32768, machine.registers[16]);
}

test "execute wraps on underflow" {
    const instruction = Instance{
        .destination = 16,
        .source = 17,
    };

    var machine = Machine.new();
    machine.registers[16] = -32768;
    machine.registers[17] = 1;

    instruction.execute(&machine);

    try testing.expectEqual(32767, machine.registers[16]);
}
