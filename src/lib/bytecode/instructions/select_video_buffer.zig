const anotherworld = @import("../../anotherworld.zig");
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const Program = @import("../program.zig").Program;
const Machine = vm.Machine;
const BufferID = vm.BufferID;

/// Select the video buffer all subsequent DrawBackgroundPolygon, DrawSpritePolygon
/// and DrawString operations will draw into.
pub const SelectVideoBuffer = struct {
    /// The buffer to select.
    buffer_id: BufferID,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 2 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const raw_id = try program.read(BufferID.Raw);

        return Self{
            .buffer_id = try BufferID.parse(raw_id),
        };
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *Machine) void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) void {
        machine.selectVideoBuffer(self.buffer_id);
    }

    // - Exported constants -

    pub const opcode = Opcode.SelectVideoBuffer;
    pub const ParseError = Program.ReadError || BufferID.Error;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [2]u8{ raw_opcode, 0x00 };

        const invalid_buffer_id = [2]u8{ raw_opcode, 0x8B };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = vm.mockMachine;

test "parse parses valid bytecode and consumes 2 bytes" {
    const instruction = try expectParse(SelectVideoBuffer.parse, &SelectVideoBuffer.Fixtures.valid, 2);

    try testing.expectEqual(.{ .specific = 0 }, instruction.buffer_id);
}

test "parse returns error.InvalidBufferID on unknown buffer identifier and consumes 2 bytes" {
    try testing.expectError(
        error.InvalidBufferID,
        expectParse(SelectVideoBuffer.parse, &SelectVideoBuffer.Fixtures.invalid_buffer_id, 2),
    );
}

test "execute calls selectVideoBuffer with correct parameters" {
    const instruction = SelectVideoBuffer{
        .buffer_id = .back_buffer,
    };

    var machine = mockMachine(struct {
        pub fn selectVideoBuffer(buffer_id: BufferID) void {
            testing.expectEqual(.back_buffer, buffer_id) catch {
                unreachable;
            };
        }
    });

    instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.selectVideoBuffer);
}
