const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig").Program;
const Machine = @import("../machine/machine.zig").Machine;
const Address = @import("../values/address.zig");

/// Unconditionally jump to a new address.
/// Unlike Call, this does not increment the stack with a return address.
pub const Jump = struct {
    /// The address to jump to.
    address: Address.Raw,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        return Self{
            .address = try program.read(Address.Raw),
        };
    }

    pub fn execute(self: Self, machine: *Machine) !void {
        try machine.program.jump(self.address);
    }

    // - Exported constants -

    pub const opcode = Opcode.Enum.Jump;
    pub const ParseError = Program.ReadError;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = @enumToInt(opcode);

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [3]u8{ raw_opcode, 0xDE, 0xAD };
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses instruction from valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(Jump.parse, &Jump.Fixtures.valid, 3);
    try testing.expectEqual(0xDEAD, instruction.address);
}

test "execute jumps to new address and does not affect stack depth" {
    const instruction = Jump{
        .address = 9,
    };

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.testInstance(.{ .bytecode = &bytecode });
    defer machine.deinit();

    try testing.expectEqual(0, machine.stack.depth);
    try testing.expectEqual(0, machine.program.counter);

    try instruction.execute(&machine);

    try testing.expectEqual(0, machine.stack.depth);
    try testing.expectEqual(9, machine.program.counter);
}

test "execute returns error.InvalidAddress when address is out of range" {
    const instruction = Jump{
        .address = 1000,
    };

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.testInstance(.{ .bytecode = &bytecode });
    defer machine.deinit();

    try testing.expectError(error.InvalidAddress, instruction.execute(&machine));
}
