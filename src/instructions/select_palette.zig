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
/// Consumes 2 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const raw_id = try program.read(PaletteID.Raw);

    return Instance{
        .palette_id = try PaletteID.parse(raw_id),
    };
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.SelectPalette);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [2]u8{ raw_opcode, 31 };

    const invalid_palette_id = [2]u8{ raw_opcode, 32 };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("test_helpers/mock_machine.zig");

test "parse parses valid bytecode and consumes 2 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 2);

    testing.expectEqual(31, instruction.palette_id);
}

test "parse returns error.InvalidPaletteID on unknown palette identifier and consumes 2 bytes" {
    testing.expectError(
        error.InvalidPaletteID,
        expectParse(parse, &BytecodeExamples.invalid_palette_id, 2),
    );
}

test "execute calls selectPalette with correct parameters" {
    const instruction = Instance{
        .palette_id = 16,
    };

    var machine = MockMachine.new(struct {
        pub fn selectPalette(palette_id: PaletteID.Trusted) void {
            testing.expectEqual(16, palette_id);
        }
    });

    instruction._execute(&machine);
    testing.expectEqual(1, machine.call_counts.selectPalette);
}
