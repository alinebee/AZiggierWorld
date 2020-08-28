const opcode = @import("opcode.zig");
const thread_id = @import("thread_id.zig");


pub const Error = thread_id.Error || OperationError || error {
    /// The end thread came before the start thread.
    InvalidThreadRange,
};

/// Resumes, suspends or deactivates one or more threads.
pub const Instruction = struct {
    /// The ID of the minimum thread to activate.
    /// Each thread between start_thread_id and end_thread_id inclusive
    /// will be affected by the operation.
    start_thread_id: thread_id.ThreadID,

    /// The ID of the maximum thread to activate.
    /// Each thread between start_thread_id and start_thread_id inclusive
    /// will be affected by the operation.
    end_thread_id: thread_id.ThreadID,

    /// The operation to perform on the threads in the range.
    operation: Operation,

    /// Parse the instruction from a bytecode reader.
    /// Consumes 3 bytes from the reader on success.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(comptime ReaderType: type, raw_opcode: opcode.RawOpcode, reader: ReaderType) !Instruction {
        const instruction = Instruction {
            .start_thread_id = try thread_id.parse(try reader.readByte()),
            .end_thread_id = try thread_id.parse(try reader.readByte()),
            .operation = try Operation.parse(try reader.readByte()),
        };

        if (instruction.start_thread_id > instruction.end_thread_id) {
            return Error.InvalidThreadRange;
        }

        return instruction;
    }

    pub fn execute(self: Instruction) !void {
        // TODO: operate on the state of a VM object
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
const debugParseInstruction = @import("test_helpers.zig").debugParseInstruction;

test "Instruction.parse parses valid bytecode" {
    const instruction = try debugParseInstruction(Instruction, &BytecodeExamples.valid);
    
    testing.expectEqual(instruction.start_thread_id, thread_id.max - 1);
    testing.expectEqual(instruction.end_thread_id, thread_id.max);
    testing.expectEqual(instruction.operation, .Deactivate);
}

test "Instruction.parse returns Error.InvalidThreadID when start thread ID is invalid" {
    testing.expectError(
        Error.InvalidThreadID,
        debugParseInstruction(Instruction, &BytecodeExamples.invalid_start_thread_id),
    );
}

test "Instruction.parse returns Error.InvalidThreadID when end thread ID is invalid" {
    testing.expectError(
        error.InvalidThreadID,
        debugParseInstruction(Instruction, &BytecodeExamples.invalid_end_thread_id),
    );
}

test "Instruction.parse returns Error.InvalidThreadRange when thread range is transposed" {
    testing.expectError(
        error.InvalidThreadRange,
        debugParseInstruction(Instruction, &BytecodeExamples.transposed_thread_ids),
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

test "parse fails to parse incomplete bytecode" {
    testing.expectError(
        error.EndOfStream,
        debugParseInstruction(Instruction, BytecodeExamples.valid[0..3]),
    );
}
