const Opcode = @import("../values/opcode.zig");
const ThreadID = @import("../values/thread_id.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const Operation = @import("thread_operation.zig");

pub const Error = Program.Error || ThreadID.Error || Operation.Error || error{
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
        const start = self.start_thread_id;
        const end = @as(usize, self.end_thread_id) + 1;

        for (machine.threads[start..end]) |*thread| {
            switch (self.operation) {
                .Resume => thread.scheduleResume(),
                .Suspend => thread.scheduleSuspend(),
                .Deactivate => thread.scheduleDeactivate(),
            }
        }
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 4 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const raw_start_thread = try program.read(ThreadID.Raw);
    const raw_end_thread = try program.read(ThreadID.Raw);
    const raw_operation = try program.read(Operation.Raw);

    const instruction = Instance{
        .start_thread_id = try ThreadID.parse(raw_start_thread),
        .end_thread_id = try ThreadID.parse(raw_end_thread),
        .operation = try Operation.parse(raw_operation),
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
    pub const valid = [4]u8{ raw_opcode, 62, 63, 0x02 };

    /// Example bytecode with an invalid starting thread ID that should produce an error.
    const invalid_start_thread_id = [4]u8{ raw_opcode, 64, 64, 0x02 };

    /// Example bytecode with an invalid ending thread ID that should produce an error.
    const invalid_end_thread_id = [4]u8{ raw_opcode, 63, 64, 0x02 };

    /// Example bytecode with a start thread ID higher than its end thread ID, which should produce an error.
    const transposed_thread_ids = [_]u8{ raw_opcode, 63, 62, 0x02 };

    /// Example bytecode with an invalid operation that should produce an error.
    const invalid_operation = [_]u8{ raw_opcode, 62, 63, 0x02 };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses valid bytecode and consumes 4 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 4);

    try testing.expectEqual(62, instruction.start_thread_id);
    try testing.expectEqual(63, instruction.end_thread_id);
    try testing.expectEqual(.Deactivate, instruction.operation);
}

test "parse returns error.InvalidThreadID and consumes 4 bytes when start thread ID is invalid" {
    try testing.expectError(
        error.InvalidThreadID,
        expectParse(parse, &BytecodeExamples.invalid_start_thread_id, 4),
    );
}

test "parse returns error.InvalidThreadID and consumes 4 bytes when end thread ID is invalid" {
    try testing.expectError(
        error.InvalidThreadID,
        expectParse(parse, &BytecodeExamples.invalid_end_thread_id, 4),
    );
}

test "parse returns error.InvalidThreadRange and consumes 4 bytes when thread range is transposed" {
    try testing.expectError(
        error.InvalidThreadRange,
        expectParse(parse, &BytecodeExamples.transposed_thread_ids, 4),
    );
}

test "execute with resume operation schedules specified threads to resume" {
    const instruction = Instance{
        .start_thread_id = 1,
        .end_thread_id = 3,
        .operation = .Resume,
    };

    var machine = Machine.new();
    for (machine.threads) |thread| {
        try testing.expectEqual(null, thread.scheduled_suspend_state);
    }

    instruction.execute(&machine);
    for (machine.threads) |thread, index| {
        switch (index) {
            1...3 => try testing.expectEqual(.running, thread.scheduled_suspend_state),
            else => try testing.expectEqual(null, thread.scheduled_suspend_state),
        }
    }
}

test "execute with suspend operation schedules specified threads to suspend" {
    const instruction = Instance{
        .start_thread_id = 1,
        .end_thread_id = 3,
        .operation = .Suspend,
    };

    var machine = Machine.new();
    for (machine.threads) |thread| {
        try testing.expectEqual(null, thread.scheduled_suspend_state);
    }

    instruction.execute(&machine);
    for (machine.threads) |thread, index| {
        switch (index) {
            1...3 => try testing.expectEqual(.suspended, thread.scheduled_suspend_state),
            else => try testing.expectEqual(null, thread.scheduled_suspend_state),
        }
    }
}

test "execute with deactivate operation schedules specified threads to deactivate" {
    const instruction = Instance{
        .start_thread_id = 1,
        .end_thread_id = 3,
        .operation = .Deactivate,
    };

    var machine = Machine.new();
    for (machine.threads) |thread| {
        try testing.expectEqual(null, thread.scheduled_execution_state);
    }

    instruction.execute(&machine);
    for (machine.threads) |thread, index| {
        switch (index) {
            1...3 => try testing.expectEqual(.inactive, thread.scheduled_execution_state),
            else => try testing.expectEqual(null, thread.scheduled_execution_state),
        }
    }
}

const math = @import("std").math;

test "execute safely iterates full range of threads" {
    const instruction = Instance{
        .start_thread_id = math.minInt(ThreadID.Trusted),
        .end_thread_id = math.maxInt(ThreadID.Trusted),
        .operation = .Resume,
    };

    var machine = Machine.new();
    for (machine.threads) |thread| {
        try testing.expectEqual(null, thread.scheduled_suspend_state);
    }

    instruction.execute(&machine);
    for (machine.threads) |thread| {
        try testing.expectEqual(.running, thread.scheduled_suspend_state);
    }
}
