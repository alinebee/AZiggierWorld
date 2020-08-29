
const opcode = @import("types/opcode.zig");
const thread_id = @import("types/thread_id.zig");
const program = @import("types/program.zig");
const thread = @import("types/thread.zig");

const VirtualMachine = @import("virtual_machine.zig").VirtualMachine;

pub const Error = program.Error || thread_id.Error;

/// Activate a specific thread and move its program counter to the specified address.
/// Takes effect on the next iteration of the run loop.
pub const Instruction = struct {
    /// The thread to activate.
    thread_id: thread_id.ThreadID,

    /// The program address that the thread should jump to when activated.
    address: program.Address,

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(raw_opcode: opcode.RawOpcode, prog: *program.Program) Error!Instruction {
        return Instruction {
            .thread_id = try thread_id.parse(try prog.read(thread_id.RawThreadID)),
            .address = try prog.read(program.Address),
        };
    }

    pub fn execute(self: Instruction, vm: *VirtualMachine) void {
        vm.threads[self.thread_id].scheduleJump(self.address);
    }
};

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(opcode.Opcode.ActivateThread);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [_]u8 { raw_opcode, thread_id.max, 0xDE, 0xAD };

    /// Example bytecode with an invalid thread ID that should produce an error.
    const invalid_thread_id = [_]u8 { raw_opcode, @as(thread_id.RawThreadID, thread_id.max) + 1, 0xDE, 0xAD };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const debugParseInstruction = @import("instruction_test_helpers.zig").debugParseInstruction;

test "parse parses instruction from valid bytecode and consumes 3 bytes" {
    const instruction = try debugParseInstruction(Instruction, &BytecodeExamples.valid, 3);
    
    testing.expectEqual(thread_id.max, instruction.thread_id);
    testing.expectEqual(0xDEAD, instruction.address);
}

test "parse returns error.InvalidThreadID and consumes 1 byte when thread ID is invalid" {
    testing.expectError(
        error.InvalidThreadID,
        debugParseInstruction(Instruction, &BytecodeExamples.invalid_thread_id, 1),
    );
}

test "parse fails to parse incomplete bytecode and consumes all remaining bytes" {
    testing.expectError(
        error.EndOfProgram,
        debugParseInstruction(Instruction, BytecodeExamples.valid[0..3], 2),
    );
}

test "execute schedules specified thread to jump to specified address" {
    const instruction = Instruction {
        .thread_id = thread_id.max,
        .address = 0xDEAD,
    };

    var vm = VirtualMachine.init();
    instruction.execute(&vm);

    testing.expectEqual(
        thread.ExecutionState { .active = 0xDEAD },
        vm.threads[thread_id.max].scheduled_execution_state,
    );
}