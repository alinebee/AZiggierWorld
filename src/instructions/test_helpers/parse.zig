//! Functions and types used when testing virtual machine instructions.

const Opcode = @import("../../values/opcode.zig");
const Program = @import("../../machine/program.zig");

const introspection = @import("../../utils/introspection.zig");

// -- Test helpers --

fn returnType(comptime parseFn: anytype) type {
    const error_type = introspection.errorType(parseFn);
    const payload_type = introspection.payloadType(parseFn);
    return (Error || error_type)!payload_type;
}

/// Try to parse a literal sequence of bytecode into a specific instruction;
/// on success or failure, check that the expected number of bytes were consumed.
pub fn expectParse(comptime parseFn: anytype, bytecode: []const u8, expected_bytes_consumed: usize) returnType(parseFn) {
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

const Error = error{
    /// The instruction consumed too few bytes from the program.
    UnderRead,
    /// The instruction consumed too many bytes from the program.
    OverRead,
};

// -- Test helpers --

const EmptyInstruction = struct {};

/// A fake instruction parse function that does nothing but consume 5 bytes
/// from the passed-in program after the opcode byte.
fn parse5MoreBytes(raw_opcode: Opcode.Raw, program: *Program.Instance) Program.Error!EmptyInstruction {
    try program.skip(5);
    return EmptyInstruction{};
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "expectParse returns parsed instruction if all bytes were parsed" {
    const bytecode = [_]u8{0} ** 6;

    const instruction = try expectParse(parse5MoreBytes, &bytecode, 6);
    testing.expectEqual(EmptyInstruction{}, instruction);
}

test "expectParse returns error.UnderRead if too few bytes were parsed" {
    const bytecode = [_]u8{0} ** 6;

    testing.expectError(error.UnderRead, expectParse(parse5MoreBytes, &bytecode, 7));
}

test "expectParse returns error.OverRead if too many bytes were parsed" {
    const bytecode = [_]u8{0} ** 6;

    testing.expectError(error.OverRead, expectParse(parse5MoreBytes, &bytecode, 3));
}
