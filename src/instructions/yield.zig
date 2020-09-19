const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const Action = @import("action.zig");

pub const Error = Program.Error;

/// Immediately moves execution to the next thread.
pub const Instance = struct {
    pub fn execute(self: Instance, machine: *Machine.Instance) Action.Enum {
        return .YieldToNextThread;
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 1 byte from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    return Instance{};
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.Yield);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [1]u8{raw_opcode};
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses instruction from valid bytecode and consumes 1 byte" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 1);
    testing.expectEqual(Instance{}, instruction);
}

test "execute returns YieldToNextThread action" {
    const instruction = Instance{};

    var machine = Machine.new();
    testing.expectEqual(.YieldToNextThread, instruction.execute(&machine));
}
