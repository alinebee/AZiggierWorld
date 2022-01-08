const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const Action = @import("action.zig");

/// Immediately moves execution to the next thread.
pub const Instance = struct {
    pub fn execute(_: Instance, machine: *Machine.Instance) ExecutionError!Action.Enum {
        // The stack is cleared between each thread execution, so yielding
        // the thread with a non-empty stack (i.e. in the middle of a function)
        // would cause the return address for the current function to be lost
        // once the next thread starts execution.
        //
        // When the thread resumes executing the function next tic, any `Return`
        // instruction within that function would result in `error.StackUnderflow`.
        //
        // We're treating this as a programmer error, but it's possible that
        // the original game's code contains functions that *only* yield
        // and never return. If so, we should remove this safety check.
        if (machine.stack.depth > 0) {
            return error.YieldWithinFunction;
        }
        return .YieldToNextThread;
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 1 byte from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, _: *Program.Instance) ParseError!Instance {
    return Instance{};
}

pub const ExecutionError = error{
    /// Attempted to yield within a function call, which would lose stack information
    // and cause a stack underflow upon resuming and returning from the function.
    YieldWithinFunction,
};

pub const ParseError = Program.Error;

// -- Bytecode examples --

pub const Fixtures = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.Yield);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [1]u8{raw_opcode};
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses instruction from valid bytecode and consumes 1 byte" {
    const instruction = try expectParse(parse, &Fixtures.valid, 1);
    try testing.expectEqual(Instance{}, instruction);
}

test "execute returns YieldToNextThread action" {
    const instruction = Instance{};

    var machine = Machine.testInstance(null);
    defer machine.deinit();

    try testing.expectEqual(.YieldToNextThread, try instruction.execute(&machine));
}

test "execute on a non-empty stack returns error.YieldWithinFunction" {
    const instruction = Instance{};

    var machine = Machine.testInstance(null);
    defer machine.deinit();

    try machine.stack.push(0x1);
    try testing.expectError(error.YieldWithinFunction, instruction.execute(&machine));
}
