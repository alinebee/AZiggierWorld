const anotherworld = @import("../../anotherworld.zig");
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const Program = @import("../program.zig").Program;
const Machine = vm.Machine;
const RegisterID = vm.RegisterID;

/// Add the value from one register to another, wrapping on overflow.
pub const RegisterAdd = struct {
    /// The ID of the register to add to.
    destination: RegisterID,

    /// The ID of the register containing the value to add.
    source: RegisterID,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        return Self{
            .destination = RegisterID.cast(try program.read(RegisterID.Raw)),
            .source = RegisterID.cast(try program.read(RegisterID.Raw)),
        };
    }

    pub fn execute(self: Self, machine: *Machine) void {
        const source_value = machine.registers.signed(self.source);
        const destination_value = machine.registers.signed(self.destination);

        // Zig syntax: +% wraps on overflow, whereas + traps.
        const new_value = source_value +% destination_value;
        machine.registers.setSigned(self.destination, new_value);
    }

    // - Exported constants -

    pub const opcode = Opcode.RegisterAdd;
    pub const ParseError = Program.ReadError;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [3]u8{ raw_opcode, 16, 17 };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(RegisterAdd.parse, &RegisterAdd.Fixtures.valid, 3);

    try testing.expectEqual(RegisterID.cast(16), instruction.destination);
    try testing.expectEqual(RegisterID.cast(17), instruction.source);
}

test "execute adds to destination register and leaves source register alone" {
    const instruction = RegisterAdd{
        .destination = RegisterID.cast(16),
        .source = RegisterID.cast(17),
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setSigned(instruction.destination, 125);
    machine.registers.setSigned(instruction.source, -50);

    instruction.execute(&machine);

    try testing.expectEqual(75, machine.registers.signed(instruction.destination));
    try testing.expectEqual(-50, machine.registers.signed(instruction.source));
}

test "execute wraps on overflow" {
    const instruction = RegisterAdd{
        .destination = RegisterID.cast(16),
        .source = RegisterID.cast(17),
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setSigned(instruction.destination, 32767);
    machine.registers.setSigned(instruction.source, 1);

    instruction.execute(&machine);

    try testing.expectEqual(-32768, machine.registers.signed(instruction.destination));
}

test "execute wraps on underflow" {
    const instruction = RegisterAdd{
        .destination = RegisterID.cast(16),
        .source = RegisterID.cast(17),
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.registers.setSigned(instruction.destination, -32768);
    machine.registers.setSigned(instruction.source, -1);

    instruction.execute(&machine);

    try testing.expectEqual(32767, machine.registers.signed(instruction.destination));
}
