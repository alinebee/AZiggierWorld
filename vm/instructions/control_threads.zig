const Opcode = @import("../types/opcode.zig");
const ThreadID = @import("../types/thread_id.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");
const Operation = @import("thread_operation.zig");

pub const Error = Program.Error || ThreadID.Error || Operation.Error || error {
    /// The end thread came before the start thread.
    InvalidThreadRange,
};

/// Resumes, suspends or deactivates one or more threads.
pub const Instance = struct {
    /// The ID of the minimum thread to operate upon.
    /// The operation will affect each thread from start_thread_id up to and including end_thread_id.
    start_thread_id: ThreadID.Trusted,

    /// The ID of the maximum thread to operate upon.
    /// The operation will affect each thread from start_thread_id up to and including end_thread_id.
    end_thread_id: ThreadID.Trusted,

    /// The operation to perform on the threads in the range.
    operation: Operation.Enum,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
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

/// Parse the next instruction from a bytecode program.
/// Consumes 3 bytes from the bytecode on success.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const instruction = Instance {
        .start_thread_id = try ThreadID.parse(try program.read(ThreadID.Raw)),
        .end_thread_id = try ThreadID.parse(try program.read(ThreadID.Raw)),
        .operation = try Operation.parse(try program.read(Operation.Raw)),
    };

    if (instruction.start_thread_id > instruction.end_thread_id) {
        return error.InvalidThreadRange;
    }

    return instruction;
}

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

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try debugParseInstruction(parse, &BytecodeExamples.valid, 3);
    
    testing.expectEqual(62, instruction.start_thread_id);
    testing.expectEqual(63, instruction.end_thread_id);
    testing.expectEqual(.Deactivate, instruction.operation);
}

test "parse returns Error.InvalidThreadID and consumes 1 byte when start thread ID is invalid" {
    testing.expectError(
        Error.InvalidThreadID,
        debugParseInstruction(parse, &BytecodeExamples.invalid_start_thread_id, 1),
    );
}

test "parse returns Error.InvalidThreadID and consumes 2 bytes when end thread ID is invalid" {
    testing.expectError(
        error.InvalidThreadID,
        debugParseInstruction(parse, &BytecodeExamples.invalid_end_thread_id, 2),
    );
}

test "parse returns Error.InvalidThreadRange and consumes 3 bytes when thread range is transposed" {
    testing.expectError(
        error.InvalidThreadRange,
        debugParseInstruction(parse, &BytecodeExamples.transposed_thread_ids, 3),
    );
}

test "parse fails to parse incomplete bytecode and consumes all available bytes" {
    testing.expectError(
        error.EndOfProgram,
        debugParseInstruction(parse, BytecodeExamples.valid[0..3], 2),
    );
}

test "execute with resume operation schedules specified threads to resume" {
    const instruction = Instance {
        .start_thread_id = 1,
        .end_thread_id = 3,
        .operation = .Resume,
    };

    var machine = Machine.new();

    testing.expectEqual(null, machine.threads[1].scheduled_suspend_state);
    testing.expectEqual(null, machine.threads[2].scheduled_suspend_state);
    testing.expectEqual(null, machine.threads[3].scheduled_suspend_state);

    instruction.execute(&machine);

    testing.expectEqual(.running, machine.threads[1].scheduled_suspend_state);
    testing.expectEqual(.running, machine.threads[2].scheduled_suspend_state);
    testing.expectEqual(.running, machine.threads[3].scheduled_suspend_state);
}

test "execute with suspend operation schedules specified threads to suspend" {
    const instruction = Instance {
        .start_thread_id = 1,
        .end_thread_id = 3,
        .operation = .Suspend,
    };

    var machine = Machine.new();

    testing.expectEqual(null, machine.threads[1].scheduled_suspend_state);
    testing.expectEqual(null, machine.threads[2].scheduled_suspend_state);
    testing.expectEqual(null, machine.threads[3].scheduled_suspend_state);

    instruction.execute(&machine);

    testing.expectEqual(.suspended, machine.threads[1].scheduled_suspend_state);
    testing.expectEqual(.suspended, machine.threads[2].scheduled_suspend_state);
    testing.expectEqual(.suspended, machine.threads[3].scheduled_suspend_state);
}

test "execute with deactivate operation schedules specified threads to deactivate" {
    const instruction = Instance {
        .start_thread_id = 1,
        .end_thread_id = 3,
        .operation = .Deactivate,
    };

    var machine = Machine.new();

    testing.expectEqual(null, machine.threads[1].scheduled_execution_state);
    testing.expectEqual(null, machine.threads[2].scheduled_execution_state);
    testing.expectEqual(null, machine.threads[3].scheduled_execution_state);

    instruction.execute(&machine);

    testing.expectEqual(.inactive, machine.threads[1].scheduled_execution_state);
    testing.expectEqual(.inactive, machine.threads[2].scheduled_execution_state);
    testing.expectEqual(.inactive, machine.threads[3].scheduled_execution_state);
}