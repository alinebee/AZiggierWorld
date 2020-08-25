
const opcode = @import("opcode.zig");
const thread_id = @import("thread_id.zig");

/// The address to a location in the current program,
/// stored in bytecode as a 16-bit big-endian unsigned integer.
const Address = u16;

/// Activate a specific thread and move its program counter to the specified address.
/// Takes effect on the next iteration of the run loop.
pub const Instruction = struct {
    /// The thread to activate.
    thread_id: thread_id.ThreadID,

    /// The program address that the thread should jump to upon activation.
    address: Address,

    /// Parse the instruction from a bytecode reader.
    /// Consumes 3 bytes from the reader on success.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(comptime ReaderType: type, raw_opcode: opcode.RawOpcode, reader: ReaderType) !Instruction {
        return Instruction {
            .thread_id = try thread_id.parseThreadID(try reader.readByte()),
            .address = try reader.readInt(Address, .Big),
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
const debugParseInstruction = @import("test_helpers.zig").debugParseInstruction;

test "parse parses instruction from valid bytecode" {
    const instruction = try debugParseInstruction(Instruction, &BytecodeExamples.valid);
    
    testing.expectEqual(instruction.thread_id, 0x01);
    testing.expectEqual(instruction.address, 0xDE_AD);
}

test "parse fails to parse invalid bytecode" {
    testing.expectError(
        thread_id.Error.InvalidThreadID, 
        debugParseInstruction(Instruction, &BytecodeExamples.invalid_thread_id),
    );
}

test "parse fails to parse incomplete bytecode" {
    testing.expectError(
        error.EndOfStream,
        debugParseInstruction(Instruction, BytecodeExamples.valid[0..2]),
    );
}
