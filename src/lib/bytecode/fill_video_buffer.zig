const anotherworld = @import("../anotherworld.zig");
const vm = anotherworld.vm;

const Opcode = @import("opcode.zig").Opcode;
const Program = vm.Program;
const Machine = vm.Machine;
const BufferID = vm.BufferID;
const ColorID = anotherworld.rendering.ColorID;

/// Fill a specified video buffer with a single color.
pub const FillVideoBuffer = struct {
    /// The buffer to fill.
    buffer_id: BufferID,
    /// The color to fill with.
    color_id: ColorID,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const raw_buffer_id = try program.read(BufferID.Raw);
        const raw_color_id = try program.read(ColorID.Raw);

        return FillVideoBuffer{
            .buffer_id = try BufferID.parse(raw_buffer_id),
            .color_id = try ColorID.parse(raw_color_id),
        };
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *Machine) void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) void {
        machine.fillVideoBuffer(self.buffer_id, self.color_id);
    }

    // - Exported constants -
    pub const opcode = Opcode.FillVideoBuffer;
    pub const ParseError = Program.ReadError || BufferID.Error || ColorID.Error;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [3]u8{ raw_opcode, 0x00, 0x01 };

        const invalid_buffer_id = [3]u8{ raw_opcode, 0x8B, 0x01 };
        const invalid_color_id = [3]u8{ raw_opcode, 0x00, 0xFF };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = vm.mockMachine;

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(FillVideoBuffer.parse, &FillVideoBuffer.Fixtures.valid, 3);

    try testing.expectEqual(.{ .specific = 0 }, instruction.buffer_id);
    try testing.expectEqual(ColorID.cast(1), instruction.color_id);
}

test "parse returns error.InvalidBufferID on unknown buffer identifier and consumes 3 bytes" {
    try testing.expectError(
        error.InvalidBufferID,
        expectParse(FillVideoBuffer.parse, &FillVideoBuffer.Fixtures.invalid_buffer_id, 3),
    );
}

test "parse returns error.InvalidColorID on unknown color and consumes 3 bytes" {
    try testing.expectError(
        error.InvalidColorID,
        expectParse(FillVideoBuffer.parse, &FillVideoBuffer.Fixtures.invalid_color_id, 3),
    );
}

test "execute calls fillVideoBuffer with correct parameters" {
    const instruction = FillVideoBuffer{
        .buffer_id = .back_buffer,
        .color_id = ColorID.cast(12),
    };

    var machine = mockMachine(struct {
        pub fn fillVideoBuffer(buffer_id: BufferID, color_id: ColorID) void {
            testing.expectEqual(.back_buffer, buffer_id) catch {
                unreachable;
            };
            testing.expectEqual(ColorID.cast(12), color_id) catch {
                unreachable;
            };
        }
    });

    instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.fillVideoBuffer);
}
