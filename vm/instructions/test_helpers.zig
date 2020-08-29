//! Functions and types used when testing virtual machine instructions.

const opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");

// -- Test helpers --

/// Try to parse a literal sequence of bytecode into a specific instruction;
/// on success or failure, check that the expected number of bytes were consumed.
pub fn debugParseInstruction(comptime Instruction: type, bytecode: []const u8, expected_bytes_consumed: usize) !Instruction {
    var program = Program.init(bytecode);
    const raw_opcode = try program.read(u8);

    const instruction = Instruction.parse(raw_opcode, &program);

    // Regardless of success or failure, check how many bytes were actually consumed.
    // (Don't count the initial opcode byte, as it's not really "part of" the instruction
    // and will have been read separately by the instruction's caller.)
    const bytes_consumed = program.counter - 1;
    if (bytes_consumed > expected_bytes_consumed) {
        return error.OverRead;
    } else if (bytes_consumed < expected_bytes_consumed) {
        return error.UnderRead;
    }

    return instruction;
}

const Error = error {
    /// The instruction consumed too few bytes from the program.
    UnderRead,
    /// The instruction consumed too many bytes from the program.
    OverRead,
};

/// A test instruction that consumes 5 bytes (not including the opcode byte).
const Fake5ByteInstruction = struct {     
    fn parse(raw_opcode: opcode.RawOpcode, program: *Program.Instance) !Fake5ByteInstruction {
        try program.skip(5);
        return Fake5ByteInstruction { };
    }
};

/// Create a fake bytecode sequence of n bytes plus an opcode byte.
fn fakeBytecode(comptime size: usize) [size + 1]u8 {
    return [_]u8 { 0 } ** (size + 1);
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "debugParseInstruction returns parsed instruction if all bytes were parsed" {
    const bytecode = fakeBytecode(5);
    
    const instruction = try debugParseInstruction(Fake5ByteInstruction, &bytecode, 5);
    testing.expectEqual(Fake5ByteInstruction { }, instruction);
}

test "debugParseInstruction returns error.UnderRead if too few bytes were parsed" {
    const bytecode = fakeBytecode(10);

    testing.expectError(error.UnderRead, debugParseInstruction(Fake5ByteInstruction, &bytecode, 6));
}

test "debugParseInstruction returns error.OverRead if too many bytes were parsed" {
    const bytecode = fakeBytecode(10);

    testing.expectError(error.OverRead, debugParseInstruction(Fake5ByteInstruction, &bytecode, 3));
}