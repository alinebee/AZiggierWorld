const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig").Machine;
const Stack = @import("../machine/stack.zig");
const Address = @import("../values/address.zig");

pub const opcode = Opcode.Enum.Call;

/// Call into a subroutine and increment the program execution stack.
pub const Instance = struct {
    /// The address of the subroutine to call.
    address: Address.Raw,

    pub fn execute(self: Instance, machine: *Machine) ExecutionError!void {
        try machine.stack.push(machine.program.counter);
        try machine.program.jump(self.address);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 3 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) ParseError!Instance {
    return Instance{
        .address = try program.read(Address.Raw),
    };
}

pub const ExecutionError = Program.SeekError || Stack.Error || error{};
pub const ParseError = Program.ReadError;

// -- Bytecode examples --

pub const Fixtures = struct {
    const raw_opcode = @enumToInt(opcode);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [3]u8{ raw_opcode, 0xDE, 0xAD };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses instruction from valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(parse, &Fixtures.valid, 3);
    try testing.expectEqual(0xDEAD, instruction.address);
}

test "execute puts previous address on the stack and jumps to new address" {
    const instruction = Instance{
        .address = 9,
    };

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.testInstance(.{ .bytecode = &bytecode });
    defer machine.deinit();

    try testing.expectEqual(0, machine.stack.depth);
    try testing.expectEqual(0, machine.program.counter);

    try instruction.execute(&machine);

    try testing.expectEqual(1, machine.stack.depth);
    try testing.expectEqual(9, machine.program.counter);
    try testing.expectEqual(0, machine.stack.pop());
}

test "execute returns error.StackOverflow when stack is full" {
    const instruction = Instance{
        .address = 0xDEAD,
    };

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.testInstance(.{ .bytecode = &bytecode });
    defer machine.deinit();

    var remaining: usize = Stack.max_depth;
    while (remaining > 0) : (remaining -= 1) {
        try machine.stack.push(0xBEEF);
    }

    try testing.expectError(error.StackOverflow, instruction.execute(&machine));
}

test "execute returns error.InvalidAddress when address is out of range" {
    const instruction = Instance{
        .address = 1000,
    };

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.testInstance(.{ .bytecode = &bytecode });
    defer machine.deinit();

    try testing.expectError(error.InvalidAddress, instruction.execute(&machine));
}
