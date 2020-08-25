//! Functions and types intended to be shared by all virtual machine instructions.

const std = @import("std");
const opcode = @import("opcode.zig");

/// The ID of a thread, stored in bytecode as an 8-bit unsigned integer from 0-63.
pub const ThreadID = u6;
/// The address of a location in the current program, stored in bytecode as a 16-bit big-endian unsigned integer.
pub const Address = u16;

/// Domain-specific errors possible when parsing Another World bytecode.
/// Apart from these, VM functions may also return stream errors.
pub const Error = error {
    UnsupportedOpcode,
    InvalidThreadID,
};

/// Given a raw byte value, return a valid thread ID.
/// Returns an error if the value is out of range.
pub fn parseThreadID(byte: u8) Error!ThreadID {
    if (byte >= 0x40) return Error.InvalidThreadID;
    return @intCast(ThreadID, byte);
}

// -- Test helpers --

/// Try to parse a literal sequence of bytecode into a specific instruction;
/// on success, check that all bytes were fully consumed.
pub fn debugParseInstruction(comptime T: type, bytecode: []const u8) !T {
    const raw_opcode = bytecode[0];
    const reader = BytecodeStream(bytecode[1..]).reader();
    const instruction = try T.parse(@TypeOf(reader), raw_opcode, reader);

    // TODO: use a seekable stream so that we can measure how many bytes were read,
    // rather than checking for end-of-stream.
    if (reader.readByte()) {
        return TestError.IncompleteRead;
    } else |err| {
        if (err != error.EndOfStream) return err;
    }

    return instruction;
}

pub const TestError = error {
    IncompleteRead,
};

pub const BytecodeStream = std.io.fixedBufferStream;

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

const testing = @import("std").testing;

test "parseThreadID succeeds with in-bounds integer" {
    testing.expectEqual(parseThreadID(15) catch unreachable, 15);
}

test "parseThreadID returns InvalidThreadID with out-of-bounds integer" {
    testing.expectError(Error.InvalidThreadID, parseThreadID(0x40));
}

test "debugParseInstruction returns parsed instruction if all bytes were parsed" {
    const bytecode = fakeBytecode(5);
    
    const instruction = try debugParseInstruction(Fake5ByteInstruction, &bytecode);
    testing.expectEqual(@TypeOf(instruction), Fake5ByteInstruction);
}

test "debugParseInstruction returns IncompleteRead error if not all bytes were parsed" {
    const bytecode = fakeBytecode(10);

    testing.expectError(TestError.IncompleteRead, debugParseInstruction(Fake5ByteInstruction, &bytecode));
}

test "debugParseInstruction returns EndOfStream error if too many bytes were parsed" {
    const bytecode = fakeBytecode(3);

    testing.expectError(error.EndOfStream, debugParseInstruction(Fake5ByteInstruction, &bytecode));
}