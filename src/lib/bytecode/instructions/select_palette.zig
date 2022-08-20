const anotherworld = @import("../../anotherworld.zig");
const rendering = anotherworld.rendering;
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const Program = @import("../program.zig").Program;
const Machine = vm.Machine;

/// Select the active palette to render the video buffer in.
pub const SelectPalette = struct {
    /// The palette to select.
    palette_id: rendering.PaletteID,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const raw_id = try program.read(rendering.PaletteID.Raw);
        // The reference implementation consumes 16 bits but only uses the top 8 for the palette ID,
        // ignoring the bottom 8. It's unclear why two bytes were used in the original bytecode.
        // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/8afc0f7d7d47f7700ad2e7d1cad33200ad29b17f/src/vm.cpp#L211-L215
        try program.skip(1);

        return Self{
            .palette_id = try rendering.PaletteID.parse(raw_id),
        };
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *Machine) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) !void {
        try machine.selectPalette(self.palette_id);
    }

    // - Exported constants -

    pub const opcode = Opcode.SelectPalette;
    pub const ParseError = Program.ReadError || rendering.PaletteID.Error;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [3]u8{ raw_opcode, 31, 0 };

        const invalid_palette_id = [3]u8{ raw_opcode, 32, 0 };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = vm.mockMachine;

test "parse parses valid bytecode and consumes 2 bytes" {
    const instruction = try expectParse(SelectPalette.parse, &SelectPalette.Fixtures.valid, 3);

    try testing.expectEqual(rendering.PaletteID.cast(31), instruction.palette_id);
}

test "parse returns error.InvalidPaletteID on unknown palette identifier and consumes 2 bytes" {
    try testing.expectError(
        error.InvalidPaletteID,
        expectParse(SelectPalette.parse, &SelectPalette.Fixtures.invalid_palette_id, 3),
    );
}

test "execute calls selectPalette with correct parameters" {
    const instruction = SelectPalette{
        .palette_id = rendering.PaletteID.cast(16),
    };

    var machine = mockMachine(struct {
        pub fn selectPalette(palette_id: rendering.PaletteID) !void {
            try testing.expectEqual(rendering.PaletteID.cast(16), palette_id);
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.selectPalette);
}
