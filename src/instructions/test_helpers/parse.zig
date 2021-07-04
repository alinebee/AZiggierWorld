//! Functions and types used when testing virtual machine instructions.

const Opcode = @import("../../values/opcode.zig");
const Program = @import("../../machine/program.zig");

const introspection = @import("../../utils/introspection.zig");

// -- Test helpers --

/// Try to parse a literal sequence of bytecode into a specific instruction;
/// on success or failure, check that the expected number of bytes were consumed.
pub fn expectParse(comptime parseFn: anytype, bytecode: []const u8, expected_bytes_consumed: usize) ReturnType(parseFn) {
    var program = Program.new(bytecode);
    const raw_opcode = try program.read(Opcode.Raw);

    const instruction = parseFn(raw_opcode, &program);

    // Regardless of success or failure, check how many bytes were actually consumed.
    const bytes_consumed = program.counter;
    if (bytes_consumed > expected_bytes_consumed) {
        return error.OverRead;
    } else if (bytes_consumed < expected_bytes_consumed) {
        return error.UnderRead;
    }

    return instruction;
}

pub const Error = error{
    /// The instruction consumed too few bytes from the program.
    UnderRead,
    /// The instruction consumed too many bytes from the program.
    OverRead,
};

/// Calculates the return type of the expectParse generic function by combining
/// the original parse function's return type with expectParse's error set.
fn ReturnType(comptime parseFn: anytype) type {
    const error_type = introspection.ErrorType(parseFn);
    const payload_type = introspection.PayloadType(parseFn);
    return (Error || error_type)!payload_type;
}

// -- Test helpers --

const EmptyInstruction = struct {};

/// A fake instruction parse function that does nothing but consume 5 bytes
/// from the passed-in program after the opcode byte.
fn parse5MoreBytes(raw_opcode: Opcode.Raw, program: *Program.Instance) Program.Error!EmptyInstruction {
    try program.skip(5);
    return EmptyInstruction{};
}

const ParseError = error{ParsingFailed};
/// A fake instruction parse function that parses an expected number of bytes
/// but returns an error instead of an instruction.
fn parse5MoreBytesAndFail(raw_opcode: Opcode.Raw, program: *Program.Instance) !EmptyInstruction {
    try program.skip(5);
    return error.ParsingFailed;
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "expectParse returns parsed instruction if all bytes were parsed" {
    const bytecode = [_]u8{0} ** 6;

    const instruction = try expectParse(parse5MoreBytes, &bytecode, 6);
    try testing.expectEqual(EmptyInstruction{}, instruction);
}

test "expectParse returns error.UnderRead if too few bytes were parsed, even if parse returned a different error" {
    const bytecode = [_]u8{0} ** 6;

    try testing.expectError(error.UnderRead, expectParse(parse5MoreBytes, &bytecode, 7));
    try testing.expectError(error.UnderRead, expectParse(parse5MoreBytesAndFail, &bytecode, 7));
}

test "expectParse returns error.OverRead if too many bytes were parsed, even if parse returned a different error" {
    const bytecode = [_]u8{0} ** 6;

    try testing.expectError(error.OverRead, expectParse(parse5MoreBytes, &bytecode, 3));
    try testing.expectError(error.OverRead, expectParse(parse5MoreBytesAndFail, &bytecode, 3));
}
