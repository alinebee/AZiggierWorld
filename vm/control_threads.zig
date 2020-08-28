const opcode = @import("types/opcode.zig");
const thread_id = @import("types/thread_id.zig");
const program = @import("types/program.zig");

const VirtualMachine = @import("virtual_machine.zig").VirtualMachine;

pub const Error = program.Error || thread_id.Error || OperationError || error {
    /// The end thread came before the start thread.
    InvalidThreadRange,
};

/// Resumes, suspends or deactivates one or more threads.
pub const Instruction = struct {
    /// The ID of the minimum thread to operate upon.
    /// The operation will affect each thread from start_thread_id up to and including end_thread_id.
    start_thread_id: thread_id.ThreadID,

    /// The ID of the maximum thread to operate upon.
    /// The operation will affect each thread from start_thread_id up to and including end_thread_id.
    end_thread_id: thread_id.ThreadID,

    /// The operation to perform on the threads in the range.
    operation: Operation,

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(raw_opcode: opcode.RawOpcode, prog: *program.Program) Error!Instruction {
        const instruction = Instruction {
            .start_thread_id = try thread_id.parse(try prog.readByte()),
            .end_thread_id = try thread_id.parse(try prog.readByte()),
            .operation = try Operation.parse(try prog.readByte()),
        };

        if (instruction.start_thread_id > instruction.end_thread_id) {
            return error.InvalidThreadRange;
        }

        return instruction;
    }

    pub fn execute(self: Instruction, vm: *VirtualMachine) void {
        var id = self.start_thread_id;
        while (id <= self.end_thread_id) {
            var thread = &vm.threads[id];

            switch (self.operation) {
                .Resume => thread.scheduleResume(),
                .Suspend => thread.scheduleSuspend(),
                .Deactivate => thread.scheduleDeactivate(),
            }

            id += 1;
        }
    }
};

const Operation = enum {
    /// Resume a previously paused thread.
    Resume,
    /// Mark the threads as paused, but maintain their current state.
    Suspend,
    /// Mark the threads as deactivated.
    Deactivate,

    fn parse(rawOperation: u8) OperationError!Operation {
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
    const raw_opcode = @enumToInt(opcode.Opcode.ControlThreads);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [_]u8 { raw_opcode, thread_id.max - 1, thread_id.max, 0x02 };

    /// Example bytecode with an invalid starting thread ID that should produce an error.
    const invalid_start_thread_id = [_]u8 { raw_opcode, thread_id.max + 1, thread_id.max + 1, 0x02 };

    /// Example bytecode with an invalid ending thread ID that should produce an error.
    const invalid_end_thread_id = [_]u8 { raw_opcode, thread_id.max, thread_id.max + 1, 0x02 };

    /// Example bytecode with a start thread ID higher than its end thread ID, which should produce an error.
    const transposed_thread_ids = [_]u8 { raw_opcode, thread_id.max, thread_id.max - 1, 0x02 };

    /// Example bytecode with an invalid operation that should produce an error.
    const invalid_operation = [_]u8 { raw_opcode, thread_id.max - 1, thread_id.max, 0x02 };
};

// -- Tests --

const testing = @import("std").testing;
const debugParseInstruction = @import("instruction_test_helpers.zig").debugParseInstruction;

test "Instruction.parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try debugParseInstruction(Instruction, &BytecodeExamples.valid, 3);
    
    testing.expectEqual(instruction.start_thread_id, thread_id.max - 1);
    testing.expectEqual(instruction.end_thread_id, thread_id.max);
    testing.expectEqual(instruction.operation, .Deactivate);
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

test "Insutrction.parse fails to parse incomplete bytecode and consumes all available bytes" {
    testing.expectError(
        error.EndOfProgram,
        debugParseInstruction(Instruction, BytecodeExamples.valid[0..3], 2),
    );
}

test "Operation.parse parses raw operation bytes correctly" {
    testing.expectEqual(try Operation.parse(0), .Resume);
    testing.expectEqual(try Operation.parse(1), .Suspend);
    testing.expectEqual(try Operation.parse(2), .Deactivate);
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

    var vm = VirtualMachine.init();

    testing.expectEqual(vm.threads[1].scheduled_suspend_state, null);
    testing.expectEqual(vm.threads[2].scheduled_suspend_state, null);
    testing.expectEqual(vm.threads[3].scheduled_suspend_state, null);

    instruction.execute(&vm);

    testing.expectEqual(vm.threads[1].scheduled_suspend_state, .running);
    testing.expectEqual(vm.threads[2].scheduled_suspend_state, .running);
    testing.expectEqual(vm.threads[3].scheduled_suspend_state, .running);
}

test "execute with suspend operation schedules specified threads to suspend" {
    const instruction = Instruction {
        .start_thread_id = 1,
        .end_thread_id = 3,
        .operation = .Suspend,
    };

    var vm = VirtualMachine.init();

    testing.expectEqual(vm.threads[1].scheduled_suspend_state, null);
    testing.expectEqual(vm.threads[2].scheduled_suspend_state, null);
    testing.expectEqual(vm.threads[3].scheduled_suspend_state, null);

    instruction.execute(&vm);

    testing.expectEqual(vm.threads[1].scheduled_suspend_state, .suspended);
    testing.expectEqual(vm.threads[2].scheduled_suspend_state, .suspended);
    testing.expectEqual(vm.threads[3].scheduled_suspend_state, .suspended);
}

test "execute with deactivate operation schedules specified threads to deactivate" {
    const instruction = Instruction {
        .start_thread_id = 1,
        .end_thread_id = 3,
        .operation = .Deactivate,
    };

    var vm = VirtualMachine.init();

    testing.expectEqual(vm.threads[1].scheduled_execution_state, null);
    testing.expectEqual(vm.threads[2].scheduled_execution_state, null);
    testing.expectEqual(vm.threads[3].scheduled_execution_state, null);

    instruction.execute(&vm);

    testing.expectEqual(vm.threads[1].scheduled_execution_state, .inactive);
    testing.expectEqual(vm.threads[2].scheduled_execution_state, .inactive);
    testing.expectEqual(vm.threads[3].scheduled_execution_state, .inactive);
}