const instruction = @import("bytecode/instruction.zig");

pub const Instruction = instruction.Instruction;
pub const executeProgram = instruction.executeProgram;
pub const ExecutionError = instruction.ExecutionError;

pub const Program = @import("bytecode/program.zig").Program;
pub const ThreadOperation = @import("bytecode/thread_operation.zig").ThreadOperation;
pub const Opcode = @import("bytecode/opcode.zig").Opcode;
