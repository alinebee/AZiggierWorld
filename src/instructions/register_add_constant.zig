const Opcode = @import("../values/opcode.zig").Opcode;
const Register = @import("../values/register.zig");
const Program = @import("../machine/program.zig").Program;
const Machine = @import("../machine/machine.zig").Machine;
const RegisterID = @import("../values/register_id.zig");

/// Adds a signed constant value to a specific register, wrapping on overflow.
pub const RegisterAddConstant = struct {
    /// The ID of the register to add to.
    destination: RegisterID.Enum,

    /// The constant value to add to the register.
    value: Register.Signed,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 4 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        return Self{
            .destination = RegisterID.parse(try program.read(RegisterID.Raw)),
            .value = try program.read(Register.Signed),
        };
    }

    pub fn execute(self: Self, machine: *Machine) void {
        const original_value = machine.registers.signed(self.destination);
        // Zig syntax: +% wraps on overflow, whereas + traps.
        const new_value = original_value +% self.value;
        machine.registers.setSigned(self.destination, new_value);
    }

    // - Exported constants -

    pub const opcode = Opcode.RegisterAddConstant;
    pub const ParseError = Program.ReadError;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = @enumToInt(opcode);

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [4]u8{ raw_opcode, 16, 0b1011_0110, 0b0010_1011 }; // -18901 in two's complement
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 4 bytes" {
    const instruction = try expectParse(RegisterAddConstant.parse, &RegisterAddConstant.Fixtures.valid, 4);

    try testing.expectEqual(RegisterID.parse(16), instruction.destination);
    try testing.expectEqual(-18901, instruction.value);
}

test "execute adds to destination register" {
    const instruction = RegisterAddConstant{
        .destination = RegisterID.parse(16),
        .value = -1000,
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setSigned(instruction.destination, 125);

    instruction.execute(&machine);

    try testing.expectEqual(-875, machine.registers.signed(instruction.destination));
}

test "execute wraps on overflow" {
    const instruction = RegisterAddConstant{
        .destination = RegisterID.parse(16),
        .value = 32767,
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setSigned(instruction.destination, 1);

    instruction.execute(&machine);

    try testing.expectEqual(-32768, machine.registers.signed(instruction.destination));
}

test "execute wraps on underflow" {
    const instruction = RegisterAddConstant{
        .destination = RegisterID.parse(16),
        .value = -32768,
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setSigned(instruction.destination, -1);

    instruction.execute(&machine);

    try testing.expectEqual(32767, machine.registers.signed(instruction.destination));
}
