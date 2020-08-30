const Opcode = @import("../types/opcode.zig");
const ThreadID = @import("../types/thread_id.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");

pub const Error = Program.Error || ThreadID.Error || OperationError || error {
    /// The end thread came before the start thread.
    InvalidThreadRange,
};

/// Resumes, suspends or deactivates one or more threads.
pub const Instruction = struct {
    /// The ID of the minimum thread to operate upon.
    /// The operation will affect each thread from start_thread_id up to and including end_thread_id.
    start_thread_id: ThreadID.Trusted,

    /// The ID of the maximum thread to operate upon.
    /// The operation will affect each thread from start_thread_id up to and including end_thread_id.
    end_thread_id: ThreadID.Trusted,

    /// The operation to perform on the threads in the range.
    operation: Operation,

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instruction {
        const instruction = Instruction {
            .start_thread_id = try ThreadID.parse(try program.read(ThreadID.Raw)),
            .end_thread_id = try ThreadID.parse(try program.read(ThreadID.Raw)),
            .operation = try Operation.parse(try program.read(RawOperation)),
        };

        if (instruction.start_thread_id > instruction.end_thread_id) {
            return error.InvalidThreadRange;
        }

        return instruction;
    }

    pub fn execute(self: Instruction, machine: *Machine.Instance) void {
        var id = self.start_thread_id;
        while (id <= self.end_thread_id) {
            var thread = &machine.threads[id];

            switch (self.operation) {
                .Resume => thread.scheduleResume(),
                .Suspend => thread.scheduleSuspend(),
                .Deactivate => thread.scheduleDeactivate(),
            }

            id += 1;
        }
    }
};

const RawOperation = u8;

const Operation = enum {
    /// Resume a previously paused thread.
    Resume,
    /// Mark the threads as paused, but maintain their current state.
    Suspend,
    /// Mark the threads as deactivated.
    Deactivate,

    fn parse(rawOperation: RawOperation) OperationError!Operation {
        // It would be nicer to use @intToEnum, but that has undefined behaviour when the value is out of range.
        return switch (rawOperation) {
            0 => .Resume,
            1 => .Suspend,
            2 => .Deactivate,
            else => error.InvalidThreadOperation,
        };
    }
};

const OperationError = error {
    /// The bytecode specified an unknown thread operation.
    InvalidThreadOperation,
};

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.ControlThreads);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [_]u8 { raw_opcode, 62, 63, 0x02 };

    /// Example bytecode with an invalid starting thread ID that should produce an error.
    const invalid_start_thread_id = [_]u8 { raw_opcode, 64, 64, 0x02 };

    /// Example bytecode with an invalid ending thread ID that should produce an error.
    const invalid_end_thread_id = [_]u8 { raw_opcode, 63, 64, 0x02 };

    /// Example bytecode with a start thread ID higher than its end thread ID, which should produce an error.
    const transposed_thread_ids = [_]u8 { raw_opcode, 63, 62, 0x02 };

    /// Example bytecode with an invalid operation that should produce an error.
    const invalid_operation = [_]u8 { raw_opcode, 62, 63, 0x02 };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const debugParseInstruction = @import("test_helpers.zig").debugParseInstruction;

test "Instruction.parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try debugParseInstruction(Instruction, &BytecodeExamples.valid, 3);
    
    testing.expectEqual(62, instruction.start_thread_id);
    testing.expectEqual(63, instruction.end_thread_id);
    testing.expectEqual(.Deactivate, instruction.operation);
}

test "Instruction.parse returns Error.InvalidThreadID and consumes 1 byte when start thread ID is invalid" {
    testing.expectError(
        Error.InvalidThreadID,
        debugParseInstruction(Instruction, &BytecodeExamples.invalid_start_thread_id, 1),
    );
}

test "Instruction.parse returns Error.InvalidThreadID and consumes 2 bytes when end thread ID is invalid" {
    testing.expectError(
        error.InvalidThreadID,
        debugParseInstruction(Instruction, &BytecodeExamples.invalid_end_thread_id, 2),
    );
}

test "Instruction.parse returns Error.InvalidThreadRange and consumes 3 bytes when thread range is transposed" {
    testing.expectError(
        error.InvalidThreadRange,
        debugParseInstruction(Instruction, &BytecodeExamples.transposed_thread_ids, 3),
    );
}

test "Instruction.parse fails to parse incomplete bytecode and consumes all available bytes" {
    testing.expectError(
        error.EndOfProgram,
        debugParseInstruction(Instruction, BytecodeExamples.valid[0..3], 2),
    );
}

test "Operation.parse parses raw operation bytes correctly" {
    testing.expectEqual(.Resume, Operation.parse(0));
    testing.expectEqual(.Suspend, Operation.parse(1));
    testing.expectEqual(.Deactivate, Operation.parse(2));
    testing.expectError(
        error.InvalidThreadOperation,
        Operation.parse(3),
    );
}

test "execute with resume operation schedules specified threads to resume" {
    const instruction = Instruction {
        .start_thread_id = 1,
        .end_thread_id = 3,
        .operation = .Resume,
    };

    var machine = Machine.init();

    testing.expectEqual(null, machine.threads[1].scheduled_suspend_state);
    testing.expectEqual(null, machine.threads[2].scheduled_suspend_state);
    testing.expectEqual(null, machine.threads[3].scheduled_suspend_state);

    instruction.execute(&machine);

    testing.expectEqual(.running, machine.threads[1].scheduled_suspend_state);
    testing.expectEqual(.running, machine.threads[2].scheduled_suspend_state);
    testing.expectEqual(.running, machine.threads[3].scheduled_suspend_state);
}

test "execute with suspend operation schedules specified threads to suspend" {
    const instruction = Instruction {
        .start_thread_id = 1,
        .end_thread_id = 3,
        .operation = .Suspend,
    };

    var machine = Machine.init();

    testing.expectEqual(null, machine.threads[1].scheduled_suspend_state);
    testing.expectEqual(null, machine.threads[2].scheduled_suspend_state);
    testing.expectEqual(null, machine.threads[3].scheduled_suspend_state);

    instruction.execute(&machine);

    testing.expectEqual(.suspended, machine.threads[1].scheduled_suspend_state);
    testing.expectEqual(.suspended, machine.threads[2].scheduled_suspend_state);
    testing.expectEqual(.suspended, machine.threads[3].scheduled_suspend_state);
}

test "execute with deactivate operation schedules specified threads to deactivate" {
    const instruction = Instruction {
        .start_thread_id = 1,
        .end_thread_id = 3,
        .operation = .Deactivate,
    };

    var machine = Machine.init();

    testing.expectEqual(null, machine.threads[1].scheduled_execution_state);
    testing.expectEqual(null, machine.threads[2].scheduled_execution_state);
    testing.expectEqual(null, machine.threads[3].scheduled_execution_state);

    instruction.execute(&machine);

    testing.expectEqual(.inactive, machine.threads[1].scheduled_execution_state);
    testing.expectEqual(.inactive, machine.threads[2].scheduled_execution_state);
    testing.expectEqual(.inactive, machine.threads[3].scheduled_execution_state);
}