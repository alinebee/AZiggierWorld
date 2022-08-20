const anotherworld = @import("../../anotherworld.zig");
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const ThreadOperation = @import("../thread_operation.zig").ThreadOperation;
const Program = vm.Program;
const Machine = vm.Machine;
const ThreadID = vm.ThreadID;

/// Resumes, pauses or deactivates one or more threads on the next game tic.
/// Note that any threads paused or deactivated by this instruction will still
/// run to completion this tic, including the thread that executed this instruction.
pub const ControlThreads = struct {
    /// The ID of the minimum thread to operate upon.
    /// The operation will affect each thread from start_thread_id up to and including end_thread_id.
    start_thread_id: ThreadID,

    /// The ID of the maximum thread to operate upon.
    /// The operation will affect each thread from start_thread_id up to and including end_thread_id.
    end_thread_id: ThreadID,

    /// The operation to perform on the threads in the range.
    operation: ThreadOperation,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 4 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const raw_start_thread = try program.read(ThreadID.Raw);
        const raw_end_thread = try program.read(ThreadID.Raw);
        const raw_operation = try program.read(ThreadOperation.Raw);

        const instruction = Self{
            .start_thread_id = try ThreadID.parse(raw_start_thread),
            .end_thread_id = try ThreadID.parse(raw_end_thread),
            .operation = try ThreadOperation.parse(raw_operation),
        };

        if (instruction.start_thread_id.index() > instruction.end_thread_id.index()) {
            return error.InvalidThreadRange;
        }

        return instruction;
    }

    pub fn execute(self: Self, machine: *Machine) void {
        const start = self.start_thread_id.index();
        const end = self.end_thread_id.index() + 1;
        const affected_threads = machine.threads[start..end];

        for (affected_threads) |*thread| {
            switch (self.operation) {
                .@"resume" => thread.scheduleResume(),
                .pause => thread.schedulePause(),
                .deactivate => thread.scheduleDeactivate(),
            }
        }
    }

    // - Exported constants -

    pub const opcode = Opcode.ControlThreads;
    pub const ParseError = Program.ReadError || ThreadID.Error || ThreadOperation.Error || error{
        /// The end thread came before the start thread.
        InvalidThreadRange,
    };

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [4]u8{ raw_opcode, 62, 63, 0x02 };

        /// Example bytecode with an invalid starting thread ID that should produce an error.
        const invalid_start_thread_id = [4]u8{ raw_opcode, 64, 64, 0x03 };

        /// Example bytecode with an invalid ending thread ID that should produce an error.
        const invalid_end_thread_id = [4]u8{ raw_opcode, 63, 64, 0x03 };

        /// Example bytecode with an invalid operation that should produce an error.
        const invalid_operation = [_]u8{ raw_opcode, 62, 63, 0x03 };

        /// Example bytecode with a start thread ID higher than its end thread ID, which should produce an error.
        const transposed_thread_ids = [_]u8{ raw_opcode, 63, 62, 0x02 };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const static_limits = anotherworld.static_limits;

// - parse tests -

test "parse parses valid bytecode and consumes 4 bytes" {
    const instruction = try expectParse(ControlThreads.parse, &ControlThreads.Fixtures.valid, 4);

    try testing.expectEqual(ThreadID.cast(62), instruction.start_thread_id);
    try testing.expectEqual(ThreadID.cast(63), instruction.end_thread_id);
    try testing.expectEqual(.deactivate, instruction.operation);
}

test "parse returns error.InvalidThreadID and consumes 4 bytes when start thread ID is invalid" {
    try testing.expectError(
        error.InvalidThreadID,
        expectParse(ControlThreads.parse, &ControlThreads.Fixtures.invalid_start_thread_id, 4),
    );
}

test "parse returns error.InvalidThreadID and consumes 4 bytes when end thread ID is invalid" {
    try testing.expectError(
        error.InvalidThreadID,
        expectParse(ControlThreads.parse, &ControlThreads.Fixtures.invalid_end_thread_id, 4),
    );
}

test "parse returns error.InvalidOperation and consumes 4 bytes when operation is not recognized" {
    try testing.expectError(
        error.InvalidThreadOperation,
        expectParse(ControlThreads.parse, &ControlThreads.Fixtures.invalid_operation, 4),
    );
}

test "parse returns error.InvalidThreadRange and consumes 4 bytes when thread range is transposed" {
    try testing.expectError(
        error.InvalidThreadRange,
        expectParse(ControlThreads.parse, &ControlThreads.Fixtures.transposed_thread_ids, 4),
    );
}

// - execute tests -

test "execute with resume operation schedules specified threads to resume" {
    const instruction = ControlThreads{
        .start_thread_id = ThreadID.cast(1),
        .end_thread_id = ThreadID.cast(3),
        .operation = .@"resume",
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    for (machine.threads) |thread| {
        try testing.expectEqual(null, thread.scheduled_pause_state);
    }

    instruction.execute(&machine);
    for (machine.threads) |thread, index| {
        switch (index) {
            1...3 => try testing.expectEqual(.running, thread.scheduled_pause_state),
            else => try testing.expectEqual(null, thread.scheduled_pause_state),
        }
    }
}

test "execute with pause operation schedules specified threads to pause" {
    const instruction = ControlThreads{
        .start_thread_id = ThreadID.cast(1),
        .end_thread_id = ThreadID.cast(3),
        .operation = .pause,
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    for (machine.threads) |thread| {
        try testing.expectEqual(null, thread.scheduled_pause_state);
    }

    instruction.execute(&machine);
    for (machine.threads) |thread, index| {
        switch (index) {
            1...3 => try testing.expectEqual(.paused, thread.scheduled_pause_state),
            else => try testing.expectEqual(null, thread.scheduled_pause_state),
        }
    }
}

test "execute with deactivate operation schedules specified threads to deactivate" {
    const instruction = ControlThreads{
        .start_thread_id = ThreadID.cast(1),
        .end_thread_id = ThreadID.cast(3),
        .operation = .deactivate,
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

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
    const instruction = ControlThreads{
        .start_thread_id = ThreadID.cast(0),
        .end_thread_id = ThreadID.cast(static_limits.thread_count - 1),
        .operation = .@"resume",
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    for (machine.threads) |thread| {
        try testing.expectEqual(null, thread.scheduled_pause_state);
    }

    instruction.execute(&machine);
    for (machine.threads) |thread| {
        try testing.expectEqual(.running, thread.scheduled_pause_state);
    }
}
