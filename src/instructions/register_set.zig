const Opcode = @import("../values/opcode.zig");
const Register = @import("../values/register.zig");
const RegisterID = @import("../values/register_id.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");

pub const opcode = Opcode.Enum.RegisterSet;

/// Set a specific register to a constant value.
pub const Instance = struct {
    /// The ID of the register to set.
    destination: RegisterID.Enum,

    /// The constant value to set the register to.
    value: Register.Signed,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        machine.registers.setSigned(self.destination, self.value);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 4 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) ParseError!Instance {
    return Instance{
        .destination = RegisterID.parse(try program.read(RegisterID.Raw)),
        .value = try program.read(Register.Signed),
    };
}

pub const ParseError = Program.ReadError;

// -- Bytecode examples --

pub const Fixtures = struct {
    const raw_opcode = @enumToInt(opcode);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [4]u8{ raw_opcode, 16, 0b1011_0110, 0b0010_1011 }; // -18901 in two's complement
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 4 bytes" {
    const instruction = try expectParse(parse, &Fixtures.valid, 4);

    try testing.expectEqual(RegisterID.parse(16), instruction.destination);
    try testing.expectEqual(-18901, instruction.value);
}

test "execute updates specified register with value" {
    const instruction = Instance{
        .destination = RegisterID.parse(16),
        .value = -1234,
    };

    var machine = Machine.testInstance(null);
    defer machine.deinit();

    instruction.execute(&machine);

    try testing.expectEqual(-1234, machine.registers.signed(instruction.destination));
}
