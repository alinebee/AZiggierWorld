const instruction = @import("instructions/instruction.zig");

pub const Instruction = instruction.Instruction;
pub const executeProgram = instruction.executeProgram;
pub const ExecutionError = instruction.ExecutionError;
pub const ThreadOperation = @import("instructions/thread_operation.zig").ThreadOperation;
pub const Opcode = @import("instructions/opcode.zig").Opcode;
