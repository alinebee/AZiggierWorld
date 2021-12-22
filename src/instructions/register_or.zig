const Opcode = @import("../values/opcode.zig");
const Register = @import("../values/register.zig");
const RegisterID = @import("../values/register_id.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");

/// Applies a bitwise-OR mask to the value in a register.
pub const Instance = struct {
    /// The ID of the register to apply the mask to.
    destination: RegisterID.Raw,

    /// The mask to apply to the value in the register.
    value: Register.Mask,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        // Register values are signed 16-bit values, but must be treated as unsigned in order to mask them.
        const original_value = machine.registers[self.destination];
        const masked_value = @bitCast(Register.Mask, original_value) | self.value;
        machine.registers[self.destination] = @bitCast(Register.Signed, masked_value);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 4 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) Error!Instance {
    return Instance{
        .destination = try program.read(RegisterID.Raw),
        .value = try program.read(Register.Mask),
    };
}

pub const Error = Program.Error;

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.RegisterOr);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [4]u8{ raw_opcode, 16, 0b1100_0011, 0b1111_0000 };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 4);

    try testing.expectEqual(16, instruction.destination);
    try testing.expectEqual(0b1100_0011_1111_0000, instruction.value);
}

test "execute masks destination register" {
    // zig fmt: off
    const original_value    = @bitCast(Register.Signed, @as(Register.Unsigned, 0b1010_0101_1010_0101));
    const mask              = @bitCast(Register.Mask,   @as(Register.Unsigned, 0b1100_0011_1111_0000));
    const expected_value    = @bitCast(Register.Signed, @as(Register.Unsigned, 0b1110_0111_1111_0101));
    // zig fmt: on

    const instruction = Instance{
        .destination = 16,
        .value = mask,
    };

    var machine = Machine.new();
    machine.registers[16] = original_value;

    instruction.execute(&machine);

    try testing.expectEqual(expected_value, machine.registers[16]);
}
