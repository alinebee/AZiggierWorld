const Opcode = @import("../values/opcode.zig");
const Register = @import("../values/register.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const RegisterID = @import("../values/register_id.zig");

/// Adds a signed constant value to a specific register, wrapping on overflow.
pub const Instance = struct {
    /// The ID of the register to add to.
    destination: RegisterID.Raw,

    /// The constant value to add to the register.
    value: Register.Signed,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        // Zig syntax: +% wraps on overflow, whereas + traps.
        machine.registers[self.destination] +%= self.value;
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

pub const Fixtures = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.RegisterAddConstant);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [4]u8{ raw_opcode, 16, 0b1011_0110, 0b0010_1011 }; // -18901 in two's complement
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 4 bytes" {
    const instruction = try expectParse(parse, &Fixtures.valid, 4);

    try testing.expectEqual(16, instruction.destination);
    try testing.expectEqual(-18901, instruction.value);
}

test "execute adds to destination register" {
    const instruction = Instance{
        .destination = 16,
        .value = -1000,
    };

    var machine = Machine.testInstance(null);
    defer machine.deinit();

    machine.registers[16] = 125;

    instruction.execute(&machine);

    try testing.expectEqual(-875, machine.registers[16]);
}

test "execute wraps on overflow" {
    const instruction = Instance{
        .destination = 16,
        .value = 32767,
    };

    var machine = Machine.testInstance(null);
    defer machine.deinit();

    machine.registers[16] = 1;

    instruction.execute(&machine);

    try testing.expectEqual(-32768, machine.registers[16]);
}

test "execute wraps on underflow" {
    const instruction = Instance{
        .destination = 16,
        .value = -32768,
    };

    var machine = Machine.testInstance(null);
    defer machine.deinit();

    machine.registers[16] = -1;

    instruction.execute(&machine);

    try testing.expectEqual(32767, machine.registers[16]);
}
