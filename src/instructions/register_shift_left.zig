const Opcode = @import("../values/opcode.zig").Opcode;
const Register = @import("../values/register.zig");
const Program = @import("../machine/program.zig").Program;
const Machine = @import("../machine/machine.zig").Machine;
const RegisterID = @import("../values/register_id.zig").RegisterID;

const introspection = @import("../utils/introspection.zig");

/// Left-shift (<<) the bits in a register's value by a specified distance.
pub const RegisterShiftLeft = struct {
    /// The ID of the register to add to.
    destination: RegisterID,

    /// The distance to shift the value by.
    shift: Register.Shift,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const destination = RegisterID.parse(try program.read(RegisterID.Raw));

        // Bytecode stored the shift distance as an unsigned 16-bit integer,
        // even though the legal range is 0...15.
        // TODO: check if bytecode ever specifies out-of-range values;
        // if so, we should let them pass at the parsing stage and set
        // the register to 0 on execution.
        const raw_shift = try program.read(u16);

        const trusted_shift = introspection.intCast(Register.Shift, raw_shift) catch {
            return error.ShiftTooLarge;
        };

        return Self{
            .destination = destination,
            .shift = trusted_shift,
        };
    }

    pub fn execute(self: Self, machine: *Machine) void {
        // Zig is currently happy to << and >> signed values without respecting their sign bit,
        // but that doesn't seem safe and may go away in future.
        // To be sure, treat the value as a raw bit pattern.
        const original_value = machine.registers.bitPattern(self.destination);
        const shifted_value = original_value << self.shift;
        machine.registers.setBitPattern(self.destination, shifted_value);
    }

    // - Exported constants -

    pub const opcode = Opcode.RegisterShiftLeft;
    pub const ParseError = Program.ReadError || error{
        /// Bytecode specified a shift distance that was too large.
        ShiftTooLarge,
    };

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = @enumToInt(opcode);

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [4]u8{ raw_opcode, 16, 0, 8 };

        const invalid_shift = [4]u8{ raw_opcode, 16, 0, 16 };
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 4 bytes" {
    const instruction = try expectParse(RegisterShiftLeft.parse, &RegisterShiftLeft.Fixtures.valid, 4);

    try testing.expectEqual(RegisterID.parse(16), instruction.destination);
    try testing.expectEqual(8, instruction.shift);
}

test "parse returns error.ShiftTooLarge and consumes 4 bytes on invalid shift distance" {
    try testing.expectError(
        error.ShiftTooLarge,
        expectParse(RegisterShiftLeft.parse, &RegisterShiftLeft.Fixtures.invalid_shift, 4),
    );
}

test "execute shifts destination register" {
    // zig fmt: off
    const original_value: Register.BitPattern   = 0b0000_1111_1111_0000;
    const shift: Register.Shift = 3;
    const expected_value: Register.BitPattern   = 0b0111_1111_1000_0000;
    // zig fmt: on

    const instruction = RegisterShiftLeft{
        .destination = RegisterID.parse(16),
        .shift = shift,
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setBitPattern(instruction.destination, original_value);

    instruction.execute(&machine);

    try testing.expectEqual(expected_value, machine.registers.bitPattern(instruction.destination));
}
