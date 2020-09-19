const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const Video = @import("../machine/video.zig");
const BufferID = @import("../values/buffer_id.zig");
const ColorID = @import("../values/color_id.zig");

/// Fill a specified video buffer with a single color.
pub const Instance = struct {
    /// The buffer to fill.
    buffer_id: BufferID.Enum,
    /// The color to fill with.
    color_id: ColorID.Trusted,

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) void {
        machine.fillVideoBuffer(self.buffer_id, self.color_id);
    }
};

pub const Error = Program.Error || BufferID.Error || ColorID.Error;

/// Parse the next instruction from a bytecode program.
/// Consumes 2 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const raw_buffer_id = try program.read(BufferID.Raw);
    const raw_color_id = try program.read(ColorID.Raw);

    return Instance{
        .buffer_id = try BufferID.parse(raw_buffer_id),
        .color_id = try ColorID.parse(raw_color_id),
    };
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.FillVideoBuffer);

    pub const valid = [3]u8{ raw_opcode, 0x00, 0x01 };
    pub const invalid_buffer_id = [3]u8{ raw_opcode, 0x8B, 0x01 };
    pub const invalid_color_id = [3]u8{ raw_opcode, 0x00, 0xFF };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("test_helpers/mock_machine.zig");

test "parse parses valid bytecode and consumes 3 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 3);

    testing.expectEqual(.{ .specific = 0 }, instruction.buffer_id);
    testing.expectEqual(1, instruction.color_id);
}

test "parse returns error.InvalidBufferID on unknown buffer identifier and consumes 3 bytes" {
    testing.expectError(
        error.InvalidBufferID,
        expectParse(parse, &BytecodeExamples.invalid_buffer_id, 3),
    );
}

test "parse returns error.InvalidColorID on unknown color and consumes 3 bytes" {
    testing.expectError(
        error.InvalidColorID,
        expectParse(parse, &BytecodeExamples.invalid_color_id, 3),
    );
}

test "execute calls fillVideoBuffer with correct parameters" {
    const instruction = Instance{
        .buffer_id = .back_buffer,
        .color_id = 12,
    };

    var machine = MockMachine.new(struct {
        pub fn fillVideoBuffer(buffer_id: BufferID.Enum, color_id: ColorID.Trusted) void {
            testing.expectEqual(.back_buffer, buffer_id);
            testing.expectEqual(12, color_id);
        }
    });

    instruction._execute(&machine);
    testing.expectEqual(1, machine.call_counts.fillVideoBuffer);
}
