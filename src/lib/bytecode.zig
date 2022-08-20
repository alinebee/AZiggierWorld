pub const Instruction = @import("bytecode/instruction.zig").Instruction;

pub const executeProgram = @import("bytecode/execute.zig").executeProgram;
pub const ExecutionError = @import("bytecode/execute.zig").ExecutionError;

pub const Program = @import("bytecode/program.zig").Program;
pub const ThreadOperation = @import("bytecode/thread_operation.zig").ThreadOperation;
pub const Opcode = @import("bytecode/opcode.zig").Opcode;
