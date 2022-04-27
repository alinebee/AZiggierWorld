const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig").Machine;
const Stack = @import("../machine/stack.zig");

pub const opcode = Opcode.Enum.Return;

/// Return from the current subroutine and decrement the program execution stack.
pub const Instance = struct {
    pub fn execute(_: Instance, machine: *Machine) ExecutionError!void {
        const return_address = try machine.stack.pop();
        try machine.program.jump(return_address);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 1 byte from the bytecode on success, including the opcode.
pub fn parse(_: Opcode.Raw, _: *Program.Instance) ParseError!Instance {
    return Instance{};
}

pub const ExecutionError = Program.SeekError || Stack.Error;
pub const ParseError = Program.ReadError;

// -- Bytecode examples --

pub const Fixtures = struct {
    const raw_opcode = @enumToInt(opcode);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [1]u8{raw_opcode};
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses instruction from valid bytecode and consumes 1 byte" {
    _ = try expectParse(parse, &Fixtures.valid, 1);
}

test "execute jumps to previous address from the stack" {
    const instruction = Instance{};

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.testInstance(.{ .bytecode = &bytecode });
    defer machine.deinit();

    try machine.stack.push(9);

    try testing.expectEqual(1, machine.stack.depth);
    try testing.expectEqual(0, machine.program.counter);

    try instruction.execute(&machine);

    try testing.expectEqual(0, machine.stack.depth);
    try testing.expectEqual(9, machine.program.counter);
}

test "execute returns error.StackUnderflow when stack is empty" {
    const instruction = Instance{};

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    try testing.expectError(error.StackUnderflow, instruction.execute(&machine));
}
