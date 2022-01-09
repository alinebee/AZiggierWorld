const Opcode = @import("../values/opcode.zig");
const Register = @import("../values/register.zig");
const RegisterID = @import("../values/register_id.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");

pub const opcode = Opcode.Enum.RegisterAnd;

/// Applies a bitwise-AND mask to the value in a register.
pub const Instance = struct {
    /// The ID of the register to apply the mask to.
    destination: RegisterID.Enum,

    /// The bitmask to apply to the value in the register.
    value: Register.BitPattern,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        const original_value = machine.registers.bitPattern(self.destination);
        const masked_value = original_value & self.value;
        machine.registers.setBitPattern(self.destination, masked_value);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 4 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) ParseError!Instance {
    return Instance{
        .destination = RegisterID.parse(try program.read(RegisterID.Raw)),
        .value = try program.read(Register.BitPattern),
    };
}

pub const ParseError = Program.Error;

// -- Bytecode examples --

pub const Fixtures = struct {
    const raw_opcode = @enumToInt(opcode);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [4]u8{ raw_opcode, 16, 0b1100_0011, 0b1111_0000 };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(parse, &Fixtures.valid, 4);

    try testing.expectEqual(RegisterID.parse(16), instruction.destination);
    try testing.expectEqual(0b1100_0011_1111_0000, instruction.value);
}

test "execute masks destination register" {
    // zig fmt: off
    const original_value: Register.BitPattern   = 0b1010_0101_1010_0101;
    const mask: Register.BitPattern             = 0b1100_0011_1111_0000;
    const expected_value: Register.BitPattern   = 0b1000_0001_1010_0000;
    // zig fmt: on

    const instruction = Instance{
        .destination = RegisterID.parse(16),
        .value = mask,
    };

    var machine = Machine.testInstance(null);
    defer machine.deinit();

    machine.registers.setBitPattern(instruction.destination, original_value);

    instruction.execute(&machine);

    try testing.expectEqual(expected_value, machine.registers.bitPattern(instruction.destination));
}
