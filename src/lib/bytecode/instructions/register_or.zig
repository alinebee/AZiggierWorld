const anotherworld = @import("../../anotherworld.zig");
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const Register = vm.Register;
const RegisterID = vm.RegisterID;
const Program = @import("../program.zig").Program;
const Machine = vm.Machine;

/// Applies a bitwise-OR mask to the value in a register.
pub const RegisterOr = struct {
    /// The ID of the register to apply the mask to.
    destination: RegisterID,

    /// The bitmask to apply to the value in the register.
    value: Register.BitPattern,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 4 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        return Self{
            .destination = RegisterID.cast(try program.read(RegisterID.Raw)),
            .value = try program.read(Register.BitPattern),
        };
    }

    pub fn execute(self: Self, machine: *Machine) void {
        const original_value = machine.registers.bitPattern(self.destination);
        const masked_value = original_value | self.value;
        machine.registers.setBitPattern(self.destination, masked_value);
    }

    // - Exported constants -
    pub const opcode = Opcode.RegisterOr;
    pub const ParseError = Program.ReadError;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [4]u8{ raw_opcode, 16, 0b1100_0011, 0b1111_0000 };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(RegisterOr.parse, &RegisterOr.Fixtures.valid, 4);

    try testing.expectEqual(RegisterID.cast(16), instruction.destination);
    try testing.expectEqual(0b1100_0011_1111_0000, instruction.value);
}

test "execute masks destination register" {
    // zig fmt: off
    const original_value: Register.BitPattern   = 0b1010_0101_1010_0101;
    const mask: Register.BitPattern             = 0b1100_0011_1111_0000;
    const expected_value: Register.BitPattern   = 0b1110_0111_1111_0101;
    // zig fmt: on

    const instruction = RegisterOr{
        .destination = RegisterID.cast(16),
        .value = mask,
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setBitPattern(instruction.destination, original_value);

    instruction.execute(&machine);

    try testing.expectEqual(expected_value, machine.registers.bitPattern(instruction.destination));
}
