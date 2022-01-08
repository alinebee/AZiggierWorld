const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const ExecutionResult = @import("execution_result.zig");

pub const Error = Program.Error;

/// Deactivates the current thread and immediately moves execution to the next thread.
pub const Instance = struct {
    pub fn execute(_: Instance, _: *Machine.Instance) ExecutionResult.Enum {
        return .deactivate;
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 1 byte from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, _: *Program.Instance) Error!Instance {
    return Instance{};
}

// -- Bytecode examples --

pub const Fixtures = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.Kill);

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

test "execute returns ExecutionResult.deactivate" {
    const instruction = Instance{};

    var machine = Machine.testInstance(null);
    defer machine.deinit();

    try testing.expectEqual(.deactivate, instruction.execute(&machine));
}
