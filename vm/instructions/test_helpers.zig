//! Functions and types used when testing virtual machine instructions.

const std = @import("std");
const opcode = @import("opcode.zig");

// -- Test helpers --

/// A stream that reads from an array of bytes.
pub const BytecodeStream = std.io.fixedBufferStream;

/// Try to parse a literal sequence of bytecode into a specific instruction;
/// on success, check that all bytes were fully consumed.
pub fn debugParseInstruction(comptime Instruction: type, bytecode: []const u8) !Instruction {
    const raw_opcode = bytecode[0];
    const reader = BytecodeStream(bytecode[1..]).reader();
    const instruction = try Instruction.parse(@TypeOf(reader), raw_opcode, reader);

    // TODO: use a seekable stream so that we can measure how many bytes were read,
    // rather than checking for end-of-stream.
    if (reader.readByte()) {
        return Error.IncompleteRead;
    } else |err| {
        if (err != error.EndOfStream) return err;
    }

    return instruction;
}

pub const Error = error {
    IncompleteRead,
};

/// A test instruction that consumes 5 bytes plus an opcode byte.
const Fake5ByteInstruction = struct {     
    fn parse(comptime Reader: type, raw_opcode: opcode.RawOpcode, reader: Reader) !Fake5ByteInstruction {
        _ = try reader.readBytesNoEof(5);
        return Fake5ByteInstruction { };
    }
};

/// Create a fake bytecode sequence of n bytes plus an opcode byte.
fn fakeBytecode(comptime size: usize) [size + 1]u8 {
    return [_]u8 { 0 } ** (size + 1);
}

// -- Tests --

const testing = std.testing;

test "debugParseInstruction returns parsed instruction if all bytes were parsed" {
    const bytecode = fakeBytecode(5);
    
    const instruction = try debugParseInstruction(Fake5ByteInstruction, &bytecode);
    testing.expectEqual(@TypeOf(instruction), Fake5ByteInstruction);
}

test "debugParseInstruction returns IncompleteRead error if not all bytes were parsed" {
    const bytecode = fakeBytecode(10);

    testing.expectError(Error.IncompleteRead, debugParseInstruction(Fake5ByteInstruction, &bytecode));
}

test "debugParseInstruction returns EndOfStream error if too many bytes were parsed" {
    const bytecode = fakeBytecode(3);

    testing.expectError(error.EndOfStream, debugParseInstruction(Fake5ByteInstruction, &bytecode));
}