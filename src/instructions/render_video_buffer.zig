const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const Video = @import("../machine/video.zig");
const BufferID = @import("../values/buffer_id.zig");
const RegisterID = @import("../values/register_id.zig");

/// Renders the contents of a video buffer to the host screen.
pub const Instance = struct {
    /// The buffer to render.
    buffer_id: BufferID.Enum,

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) void {
        // DOCUMENTME: How many tics? to leave the previous frame on screen before rendering this one.
        // According to the reference implementation this will be a value from 1-5.
        // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/8afc0f7d7d47f7700ad2e7d1cad33200ad29b17f/src/vm.cpp#L274-L296
        const delay = @as(Video.FrameDelay, machine.registers[RegisterID.frame_duration]);

        // DOCUMENTME: Copypasta from reference implementation.
        // Unclear what this means or what it will do if we change it.
        machine.registers[RegisterID.render_video_buffer_UNKNOWN] = 0;

        machine.renderVideoBuffer(self.buffer_id, delay);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 2 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const raw_id = try program.read(BufferID.Raw);

    return Instance{
        .buffer_id = try BufferID.parse(raw_id),
    };
}

pub const Error = Program.Error || BufferID.Error;

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.RenderVideoBuffer);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [2]u8{ raw_opcode, 0xFF };

    const invalid_buffer_id = [2]u8{ raw_opcode, 0x8B };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("test_helpers/mock_machine.zig");

test "parse parses valid bytecode and consumes 2 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 2);

    try testing.expectEqual(.back_buffer, instruction.buffer_id);
}

test "parse returns error.InvalidBufferID on unknown buffer identifier and consumes 2 bytes" {
    try testing.expectError(
        error.InvalidBufferID,
        expectParse(parse, &BytecodeExamples.invalid_buffer_id, 2),
    );
}

test "execute calls renderVideoBuffer with correct parameters" {
    const instruction = Instance{
        .buffer_id = .back_buffer,
    };

    var machine = MockMachine.new(struct {
        pub fn renderVideoBuffer(buffer_id: BufferID.Enum, delay: Video.FrameDelay) void {
            testing.expectEqual(.back_buffer, buffer_id) catch { unreachable; };
            testing.expectEqual(5, delay) catch { unreachable; };
        }
    });
    machine.registers[RegisterID.frame_duration] = 5;
    machine.registers[RegisterID.render_video_buffer_UNKNOWN] = 1234;

    instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.renderVideoBuffer);

    try testing.expectEqual(0, machine.registers[RegisterID.render_video_buffer_UNKNOWN]);
}
