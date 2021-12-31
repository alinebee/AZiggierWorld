const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const Address = @import("../values/address.zig");
const RegisterID = @import("../values/register_id.zig");

pub const Error = Program.Error;

/// Decrement the value in a specific register and move the program counter to a specific address
/// if the value in that register is not yet zero. Likely used for loop counters.
pub const Instance = struct {
    /// The register storing the counter to decrement.
    register_id: RegisterID.Raw,
    /// The address to jump to if the register value is non-zero.
    address: Address.Raw,

    pub fn execute(self: Instance, machine: *Machine.Instance) !void {
        // Subtract one from the specified register, wrapping on underflow.
        // (The standard `-=` would trap on underflow, which would probably indicate
        // a bytecode bug, but the Another World VM assumed C-style integer wrapping
        // and we should respect that.)
        machine.registers[self.register_id] -%= 1;

        // If the counter register is still not zero, jump.
        if (machine.registers[self.register_id] != 0) {
            try machine.program.jump(self.address);
        }
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 4 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) Error!Instance {
    return Instance{
        .register_id = try program.read(RegisterID.Raw),
        .address = try program.read(Address.Raw),
    };
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.JumpIfNotZero);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [4]u8{ raw_opcode, 0x01, 0xDE, 0xAD };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses instruction from valid bytecode and consumes 4 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 4);
    try testing.expectEqual(1, instruction.register_id);
    try testing.expectEqual(0xDEAD, instruction.address);
}

test "execute decrements register and jumps to new address if register is still non-zero" {
    const instruction = Instance{
        .register_id = 255,
        .address = 9,
    };

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.testInstance(&bytecode);
    defer machine.deinit();

    machine.registers[255] = 2;

    try testing.expectEqual(0, machine.program.counter);

    try instruction.execute(&machine);

    try testing.expectEqual(1, machine.registers[255]);
    try testing.expectEqual(9, machine.program.counter);
}

test "execute decrements register but does not jump if register reaches zero" {
    const instruction = Instance{
        .register_id = 255,
        .address = 9,
    };

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.testInstance(&bytecode);
    defer machine.deinit();

    machine.registers[255] = 1;

    try testing.expectEqual(0, machine.program.counter);

    try instruction.execute(&machine);

    try testing.expectEqual(0, machine.registers[255]);
    try testing.expectEqual(0, machine.program.counter);
}

test "execute decrement wraps around on underflow" {
    const instruction = Instance{
        .register_id = 255,
        .address = 9,
    };

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.testInstance(&bytecode);
    defer machine.deinit();

    machine.registers[255] = -32768;

    try instruction.execute(&machine);

    try testing.expectEqual(32767, machine.registers[255]);
}

test "execute returns error.InvalidAddress on jump when address is out of range" {
    const instruction = Instance{
        .register_id = 255,
        .address = 1000,
    };

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.testInstance(&bytecode);
    defer machine.deinit();

    machine.registers[255] = 2;

    try testing.expectError(error.InvalidAddress, instruction.execute(&machine));
}
