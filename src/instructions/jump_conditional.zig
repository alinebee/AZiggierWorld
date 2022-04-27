const Opcode = @import("../values/opcode.zig").Opcode;
const Register = @import("../values/register.zig");
const Program = @import("../machine/program.zig").Program;
const Machine = @import("../machine/machine.zig").Machine;
const Comparison = @import("comparison.zig").Comparison;
const Address = @import("../values/address.zig");
const RegisterID = @import("../values/register_id.zig");

/// Compares the value in a register against another register or constant
/// and jumps to a new address in the program if the comparison succeeds.
pub const JumpConditional = struct {
    /// The register to use for the left-hand side of the condition.
    lhs: RegisterID.Enum,

    /// The register or constant to use for the right-hand side of the condition.
    rhs: union(enum) {
        constant: Register.Signed,
        register: RegisterID.Enum,
    },

    /// How to compare the two sides of the condition.
    comparison: Comparison,

    /// The program address to jump to if the condition succeeds.
    address: Address.Raw,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 6 or 7 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        var self: Self = undefined;

        // A conditional jump instruction has a control byte with the layout: `rr|000|ccc`, where:
        //
        // - `rr` determines where to read the value to compare against and thus how many bytes the instruction will read:
        //   - 11, 10: compare against value in register ID encoded in last byte (5-byte instruction)
        //   - 01: compare against signed 16-bit constant encoded in last 2 bytes (6-byte instruction)
        //   - 00: compare against unsigned 8-bit constant encoded in last byte (5-byte instruction)
        //
        // - `ccc` determines how to compare the two values:
        //   - 000: == equal
        //   - 001: != not equal
        //   - 010: >  greater than
        //   - 011: >= greater than or equal to
        //   - 100: <  less than
        //   - 101: <= less than or equal to
        //   110 and 111 are unsupported and will trigger error.InvalidJumpComparison.

        const control_code = try program.read(u8);
        // Operand source is the top 2 bits; comparison is the bottom 3 bits
        const raw_source = @truncate(u2, control_code >> 6);
        const raw_comparison = @truncate(Comparison.Raw, control_code);

        self.lhs = RegisterID.parse(try program.read(RegisterID.Raw));
        self.rhs = switch (raw_source) {
            // Even though 16-bit registers are signed, the reference implementation treats 8-bit constants as unsigned.
            0b00 => .{ .constant = try program.read(u8) },
            0b01 => .{ .constant = try program.read(Register.Signed) },
            0b10, 0b11 => .{ .register = RegisterID.parse(try program.read(RegisterID.Raw)) },
        };

        self.address = try program.read(Address.Raw);

        // Do failable parsing *after* loading all the bytes that this instruction would normally consume;
        // This way, tests that recover from failed parsing can parse the rest of the program correctly.
        self.comparison = try Comparison.parse(raw_comparison);

        return self;
    }

    pub fn execute(self: Self, machine: *Machine) !void {
        const lhs = machine.registers.signed(self.lhs);
        const rhs = switch (self.rhs) {
            .constant => |value| value,
            .register => |register_id| machine.registers.signed(register_id),
        };

        if (self.comparison.compare(lhs, rhs)) {
            try machine.program.jump(self.address);
        }
    }

    // - Exported constants -

    pub const opcode = Opcode.JumpConditional;
    pub const ParseError = Program.ReadError || Comparison.Error;

    // -- Bytecode examples --

    // zig fmt: off
    pub const Fixtures = struct {
        const raw_opcode = @enumToInt(opcode);

        /// Example bytecode that should produce a valid instruction.
        pub const valid = equal_to_const16;

        const equal_to_register = [6]u8{ raw_opcode, 0b11_000_000, 0xFF, 0x00, 0xDE, 0xAD };
        const equal_to_const16  = [7]u8{ raw_opcode, 0b01_000_000, 0xFF, 0x4B, 0x1D, 0xDE, 0xAD };
        const equal_to_const8   = [6]u8{ raw_opcode, 0b00_000_000, 0xFF, 0xBE, 0xDE, 0xAD };

        const not_equal                 = [6]u8{ raw_opcode, 0b11_000_001, 0xFF, 0x00, 0xDE, 0xAD };
        const greater_than              = [6]u8{ raw_opcode, 0b11_000_010, 0xFF, 0x00, 0xDE, 0xAD };
        const greater_than_or_equal_to  = [6]u8{ raw_opcode, 0b11_000_011, 0xFF, 0x00, 0xDE, 0xAD };
        const less_than                 = [6]u8{ raw_opcode, 0b11_000_100, 0xFF, 0x00, 0xDE, 0xAD };
        const less_than_or_equal_to     = [6]u8{ raw_opcode, 0b11_000_101, 0xFF, 0x00, 0xDE, 0xAD };
        const invalid_comparison        = [6]u8{ raw_opcode, 0b11_000_110, 0xFF, 0x00, 0xDE, 0xAD };
    };
    // zig fmt: on
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses equal_to_register instruction and consumes 6 bytes" {
    const instruction = try expectParse(JumpConditional.parse, &JumpConditional.Fixtures.equal_to_register, 6);
    const expected = JumpConditional{
        .lhs = RegisterID.parse(0xFF),
        .rhs = .{ .register = RegisterID.parse(0) },
        .comparison = .equal,
        .address = 0xDEAD,
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses equal_to_const16 instruction and consumes 7 bytes" {
    const instruction = try expectParse(JumpConditional.parse, &JumpConditional.Fixtures.equal_to_const16, 7);
    const expected = JumpConditional{
        .lhs = RegisterID.parse(0xFF),
        .rhs = .{ .constant = 0x4B1D },
        .comparison = .equal,
        .address = 0xDEAD,
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses equal_to_const8 instruction and consumes 6 bytes" {
    const instruction = try expectParse(JumpConditional.parse, &JumpConditional.Fixtures.equal_to_const8, 6);
    const expected = JumpConditional{
        .lhs = RegisterID.parse(0xFF),
        .rhs = .{ .constant = 0xBE },
        .comparison = .equal,
        .address = 0xDEAD,
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses not_equal instruction and consumes 6 bytes" {
    const instruction = try expectParse(JumpConditional.parse, &JumpConditional.Fixtures.not_equal, 6);
    const expected = JumpConditional{
        .lhs = RegisterID.parse(0xFF),
        .rhs = .{ .register = RegisterID.parse(0) },
        .comparison = .not_equal,
        .address = 0xDEAD,
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses greater_than instruction and consumes 6 bytes" {
    const instruction = try expectParse(JumpConditional.parse, &JumpConditional.Fixtures.greater_than, 6);
    const expected = JumpConditional{
        .lhs = RegisterID.parse(0xFF),
        .rhs = .{ .register = RegisterID.parse(0) },
        .comparison = .greater_than,
        .address = 0xDEAD,
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses greater_than_or_equal_to instruction and consumes 6 bytes" {
    const instruction = try expectParse(JumpConditional.parse, &JumpConditional.Fixtures.greater_than_or_equal_to, 6);
    const expected = JumpConditional{
        .lhs = RegisterID.parse(0xFF),
        .rhs = .{ .register = RegisterID.parse(0) },
        .comparison = .greater_than_or_equal_to,
        .address = 0xDEAD,
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses less_than instruction and consumes 6 bytes" {
    const instruction = try expectParse(JumpConditional.parse, &JumpConditional.Fixtures.less_than, 6);
    const expected = JumpConditional{
        .lhs = RegisterID.parse(0xFF),
        .rhs = .{ .register = RegisterID.parse(0) },
        .comparison = .less_than,
        .address = 0xDEAD,
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses less_than_or_equal_to instruction and consumes 6 bytes" {
    const instruction = try expectParse(JumpConditional.parse, &JumpConditional.Fixtures.less_than_or_equal_to, 6);
    const expected = JumpConditional{
        .lhs = RegisterID.parse(0xFF),
        .rhs = .{ .register = RegisterID.parse(0) },
        .comparison = .less_than_or_equal_to,
        .address = 0xDEAD,
    };
    try testing.expectEqual(expected, instruction);
}

test "parse returns error.InvalidJumpComparison for instruction with invalid comparison" {
    try testing.expectError(
        error.InvalidJumpComparison,
        expectParse(JumpConditional.parse, &JumpConditional.Fixtures.invalid_comparison, 6),
    );
}

test "execute compares expected registers and jumps to expected address when condition succeeds" {
    const bytecode = [_]u8{0} ** 10;
    const lhs_register = RegisterID.parse(1);
    const rhs_register = RegisterID.parse(2);

    var machine = Machine.testInstance(.{ .bytecode = &bytecode });
    defer machine.deinit();

    machine.registers.setSigned(lhs_register, 0xFF);
    machine.registers.setSigned(rhs_register, 0xFF);

    const instruction = JumpConditional{
        .lhs = lhs_register,
        .rhs = .{ .register = rhs_register },
        .comparison = .equal,
        .address = 9,
    };

    try testing.expectEqual(0, machine.program.counter);

    try instruction.execute(&machine);

    try testing.expectEqual(9, machine.program.counter);
}

test "execute compares expected register to constant and jumps to expected address when condition succeeds" {
    const bytecode = [_]u8{0} ** 10;
    const lhs_register = RegisterID.parse(1);

    var machine = Machine.testInstance(.{ .bytecode = &bytecode });
    defer machine.deinit();

    machine.registers.setSigned(lhs_register, 0x41BD);

    const instruction = JumpConditional{
        .lhs = lhs_register,
        .rhs = .{ .constant = 0x41BD },
        .comparison = .equal,
        .address = 9,
    };

    try testing.expectEqual(0, machine.program.counter);
    try instruction.execute(&machine);
    try testing.expectEqual(9, machine.program.counter);
}

test "execute does not jump when condition fails" {
    const bytecode = [_]u8{0} ** 10;
    const lhs_register = RegisterID.parse(1);
    const rhs_register = RegisterID.parse(2);

    var machine = Machine.testInstance(.{ .bytecode = &bytecode });
    defer machine.deinit();

    machine.registers.setSigned(lhs_register, 0xFF);
    machine.registers.setSigned(rhs_register, 0xFE);

    const instruction = JumpConditional{
        .lhs = lhs_register,
        .rhs = .{ .register = rhs_register },
        .comparison = .equal,
        .address = 9,
    };

    try testing.expectEqual(0, machine.program.counter);

    try instruction.execute(&machine);

    try testing.expectEqual(0, machine.program.counter);
}

test "execute returns error.InvalidAddress when address is out of range" {
    const bytecode = [_]u8{0} ** 10;
    const lhs_register = RegisterID.parse(1);
    const rhs_register = RegisterID.parse(2);

    var machine = Machine.testInstance(.{ .bytecode = &bytecode });
    defer machine.deinit();

    machine.registers.setSigned(lhs_register, 0xFF);
    machine.registers.setSigned(rhs_register, 0xFF);

    const instruction = JumpConditional{
        .lhs = lhs_register,
        .rhs = .{ .register = rhs_register },
        .comparison = .equal,
        .address = 1000,
    };

    try testing.expectError(error.InvalidAddress, instruction.execute(&machine));
}
