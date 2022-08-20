const anotherworld = @import("../../anotherworld.zig");
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const Program = @import("../program.zig").Program;
const Machine = vm.Machine;
const Stack = vm.Stack;

/// Return from the current subroutine and decrement the program execution stack.
pub const Return = struct {
    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 1 byte from the bytecode on success, including the opcode.
    pub fn parse(_: Opcode.Raw, _: *Program) ParseError!Self {
        return Self{};
    }

    pub fn execute(_: Self, machine: *Machine) ExecutionError!void {
        const return_address = try machine.stack.pop();
        try machine.program.jump(return_address);
    }

    // - Exported constants -
    pub const opcode = Opcode.Return;

    pub const ExecutionError = Program.SeekError || Stack.Error;
    pub const ParseError = Program.ReadError;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [1]u8{raw_opcode};
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses instruction from valid bytecode and consumes 1 byte" {
    _ = try expectParse(Return.parse, &Return.Fixtures.valid, 1);
}

test "execute jumps to previous address from the stack" {
    const instruction = Return{};

    const program_data = [_]u8{0} ** 10;

    var machine = Machine.testInstance(.{ .program_data = &program_data });
    defer machine.deinit();

    try machine.stack.push(9);

    try testing.expectEqual(1, machine.stack.depth);
    try testing.expectEqual(0, machine.program.counter);

    try instruction.execute(&machine);

    try testing.expectEqual(0, machine.stack.depth);
    try testing.expectEqual(9, machine.program.counter);
}

test "execute returns error.StackUnderflow when stack is empty" {
    const instruction = Return{};

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    try testing.expectError(error.StackUnderflow, instruction.execute(&machine));
}
