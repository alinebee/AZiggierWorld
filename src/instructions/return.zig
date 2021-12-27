const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const Stack = @import("../machine/stack.zig");

pub const Error = Program.Error || Stack.Error;

/// Return from the current subroutine and decrement the program execution stack.
pub const Instance = struct {
    pub fn execute(_: Instance, machine: *Machine.Instance) !void {
        const return_address = try machine.stack.pop();
        try machine.program.jump(return_address);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 1 byte from the bytecode on success, including the opcode.
pub fn parse(_: Opcode.Raw, _: *Program.Instance) Error!Instance {
    return Instance{};
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.Return);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [1]u8{raw_opcode};
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses instruction from valid bytecode and consumes 1 byte" {
    _ = try expectParse(parse, &BytecodeExamples.valid, 1);
}

test "execute jumps to previous address from the stack" {
    const instruction = Instance{};

    const bytecode = [_]u8{0} ** 10;

    var machine = Machine.test_machine(&bytecode);
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

    var machine = Machine.test_machine(null);
    defer machine.deinit();

    try testing.expectError(error.StackUnderflow, instruction.execute(&machine));
}
