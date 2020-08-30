
const Opcode = @import("../types/opcode.zig");
const ThreadID = @import("../types/thread_id.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");

pub const Error = Program.Error || ThreadID.Error;

/// Activate a specific thread and move its program counter to the specified address.
/// Takes effect on the next iteration of the run loop.
pub const Instance = struct {
    /// The thread to activate.
    thread_id: ThreadID.Trusted,

    /// The program address that the thread should jump to when activated.
    address: Program.Address,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        machine.threads[self.thread_id].scheduleJump(self.address);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 3 bytes from the bytecode on success.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    return Instance {
        .thread_id = try ThreadID.parse(try program.read(ThreadID.Raw)),
        .address = try program.read(Program.Address),
    };
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.ActivateThread);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [_]u8 { raw_opcode, 63, 0xDE, 0xAD };

    /// Example bytecode with an invalid thread ID that should produce an error.
    const invalid_thread_id = [_]u8 { raw_opcode, 255, 0xDE, 0xAD };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const debugParseInstruction = @import("test_helpers.zig").debugParseInstruction;

test "parse parses instruction from valid bytecode and consumes 3 bytes" {
    const instruction = try debugParseInstruction(parse, &BytecodeExamples.valid, 3);
    
    testing.expectEqual(63, instruction.thread_id);
    testing.expectEqual(0xDEAD, instruction.address);
}

test "parse returns error.InvalidThreadID and consumes 1 byte when thread ID is invalid" {
    testing.expectError(
        error.InvalidThreadID,
        debugParseInstruction(parse, &BytecodeExamples.invalid_thread_id, 1),
    );
}

test "parse fails to parse incomplete bytecode and consumes all remaining bytes" {
    testing.expectError(
        error.EndOfProgram,
        debugParseInstruction(parse, BytecodeExamples.valid[0..3], 2),
    );
}

test "execute schedules specified thread to jump to specified address" {
    const instruction = Instance {
        .thread_id = 63,
        .address = 0xDEAD,
    };

    var machine = Machine.new();
    instruction.execute(&machine);

    testing.expectEqual(
        .{ .active = 0xDEAD },
        machine.threads[63].scheduled_execution_state
    );
}