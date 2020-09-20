const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const RegisterID = @import("../values/register_id.zig");

const RegisterMask = u16;

/// Applies a bitwise-AND mask to the value in a register.
pub const Instance = struct {
    /// The ID of the register to apply the mask to.
    destination: RegisterID.Raw,

    /// The mask to apply to the value in the register.
    value: RegisterMask,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        // Register values are signed 16-bit values, but must be treated as unsigned in order to mask them.
        const original_value = machine.registers[self.destination];
        const masked_value = @bitCast(RegisterMask, original_value) & self.value;
        machine.registers[self.destination] = @bitCast(Machine.RegisterValue, masked_value);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 4 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    return Instance{
        .destination = try program.read(RegisterID.Raw),
        .value = try program.read(RegisterMask),
    };
}

pub const Error = Program.Error;

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.RegisterAnd);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [4]u8{ raw_opcode, 16, 0b1100_0011, 0b1111_0000 };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 4);

    testing.expectEqual(16, instruction.destination);
    testing.expectEqual(0b1100_0011_1111_0000, instruction.value);
}

test "execute masks destination register" {
    const original_value: RegisterMask = 0b1010_0101_1010_0101;
    const mask: RegisterMask = 0b1100_0011_1111_0000;
    const expected_value: RegisterMask = 0b1000_0001_1010_0000;

    const instruction = Instance{
        .destination = 16,
        .value = mask,
    };

    var machine = Machine.new();
    machine.registers[16] = @bitCast(Machine.RegisterValue, original_value);

    instruction.execute(&machine);

    testing.expectEqual(expected_value, @bitCast(RegisterMask, machine.registers[16]));
}
