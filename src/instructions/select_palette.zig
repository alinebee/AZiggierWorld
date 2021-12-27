const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const PaletteID = @import("../values/palette_id.zig");

/// Select the active palette to render the video buffer in.
pub const Instance = struct {
    /// The palette to select.
    palette_id: PaletteID.Trusted,

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) void {
        machine.selectPalette(self.palette_id);
    }
};

pub const Error = Program.Error || PaletteID.Error;

/// Parse the next instruction from a bytecode program.
/// Consumes 3 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const raw_id = try program.read(PaletteID.Raw);
    // The reference implementation consumes 16 bits but only uses the top 8 for the palette ID,
    // ignoring the bottom 8. It's unclear why two bytes were used in the original bytecode.
    // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/8afc0f7d7d47f7700ad2e7d1cad33200ad29b17f/src/vm.cpp#L211-L215
    try program.skip(1);

    return Instance{
        .palette_id = try PaletteID.parse(raw_id),
    };
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.SelectPalette);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [3]u8{ raw_opcode, 31, 0 };

    const invalid_palette_id = [3]u8{ raw_opcode, 32, 0 };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("../machine/test_helpers/mock_machine.zig");

test "parse parses valid bytecode and consumes 2 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 3);

    try testing.expectEqual(31, instruction.palette_id);
}

test "parse returns error.InvalidPaletteID on unknown palette identifier and consumes 2 bytes" {
    try testing.expectError(
        error.InvalidPaletteID,
        expectParse(parse, &BytecodeExamples.invalid_palette_id, 3),
    );
}

test "execute calls selectPalette with correct parameters" {
    const instruction = Instance{
        .palette_id = 16,
    };

    var machine = MockMachine.new(struct {
        pub fn selectPalette(palette_id: PaletteID.Trusted) void {
            testing.expectEqual(16, palette_id) catch {
                unreachable;
            };
        }
    });

    instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.selectPalette);
}
