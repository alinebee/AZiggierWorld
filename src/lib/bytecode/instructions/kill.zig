const anotherworld = @import("../../anotherworld.zig");
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const Program = vm.Program;
const Machine = vm.Machine;
const ExecutionResult = @import("../execution_result.zig").ExecutionResult;

/// Deactivates the current thread and immediately moves execution to the next thread.
pub const Kill = struct {
    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 1 byte from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, _: *Program) ParseError!Self {
        return Self{};
    }
    pub fn execute(_: Self, _: *Machine) ExecutionResult {
        return .deactivate;
    }

    // - Exported constants -
    pub const opcode = Opcode.Kill;
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
    const instruction = try expectParse(Kill.parse, &Kill.Fixtures.valid, 1);
    try testing.expectEqual(Kill{}, instruction);
}

test "execute returns ExecutionResult.deactivate" {
    const instruction = Kill{};

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    try testing.expectEqual(.deactivate, instruction.execute(&machine));
}
