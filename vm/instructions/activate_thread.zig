const vm = @import("shared.zig");
const opcode = @import("opcode.zig");

/// Activate a specific thread and move its program counter to the specified address.
/// Takes effect on the next iteration of the run loop.
pub const Instruction = struct {
    /// The thread to activate.
    thread_id: vm.ThreadID,

    /// The program address that the thread should jump to upon activation.
    address: vm.Address,

    /// Parse the instruction from a bytecode reader.
    /// Consumes 3 bytes from the reader on success.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(comptime ReaderType: type, raw_opcode: opcode.RawOpcode, reader: ReaderType) !Instruction {
        return Instruction {
            .thread_id = try vm.parseThreadID(try reader.readByte()),
            .address = try reader.readInt(vm.Address, .Big),
        };
    }

    pub fn execute(self: Instruction) !void {
        // TODO: operate on the state of a VM object
    }
};

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const opcodeByte = @enumToInt(opcode.Opcode.ActivateThread);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [_]u8 { opcodeByte, 0x01, 0xDE, 0xAD };

    /// Example bytecode with an invalid thread ID that should produce an error.
    const invalid_thread_id = [_]u8 { opcodeByte, 0xFF, 0xDE, 0xAD };
};

// -- Tests --

const testing = @import("std").testing;

test "parse parses instruction from valid bytecode" {
    const instruction = try vm.debugParseInstruction(Instruction, &BytecodeExamples.valid);
    
    testing.expectEqual(instruction.thread_id, 0x01);
    testing.expectEqual(instruction.address, 0xDE_AD);
}

test "parse fails to parse invalid bytecode" {
    testing.expectError(
        vm.Error.InvalidThreadID, 
        vm.debugParseInstruction(Instruction, &BytecodeExamples.invalid_thread_id),
    );
}

test "parse fails to parse incomplete bytecode" {
    testing.expectError(
        error.EndOfStream,
        vm.debugParseInstruction(Instruction, BytecodeExamples.valid[0..2]),
    );
}
