const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig").Program;
const Machine = @import("../machine/machine.zig").Machine;
const Video = @import("../machine/video.zig").Video;
const BufferID = @import("../values/buffer_id.zig");
const RegisterID = @import("../values/register_id.zig");

/// This instruction reads a variable from a specific register to decide how long to leave
/// the previous frame on screen before displaying the next one.
/// That register's value is a number of abstract frame units and needs to be multiplied
/// by this constant to get the delay in milliseconds.
const milliseconds_per_frame_unit: Video.Milliseconds = 20;

/// Renders the contents of a video buffer to the host screen.
pub const RenderVideoBuffer = struct {
    /// The buffer to render.
    buffer_id: BufferID.Enum,

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
        // In Another World's original bytecode, the delay is typically set to between 1-11 units (20-220 ms).
        const delay_in_frame_units = machine.registers.unsigned(.frame_duration);
        const delay_in_milliseconds = @as(Video.Milliseconds, delay_in_frame_units) * milliseconds_per_frame_unit;

        // Copypasta from reference implementation.
        // From examining Another World's bytecode, nothing else ever writes to this register;
        // since 0 is the initial value of all registers, this code effectively does nothing.
        // Some instructions do read from this register, so altering this value at compile time
        // may have some effect.
        machine.registers.setUnsigned(.render_video_buffer_UNKNOWN, 0);

        machine.renderVideoBuffer(self.buffer_id, delay_in_milliseconds);
    }

    // - Exported constants -
    pub const ParseError = Program.ReadError || BufferID.Error;
    pub const opcode = Opcode.Enum.RenderVideoBuffer;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = @enumToInt(opcode);

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [2]u8{ raw_opcode, 0xFF };

        const invalid_buffer_id = [2]u8{ raw_opcode, 0x8B };
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = @import("../machine/test_helpers/mock_machine.zig").mockMachine;

test "parse parses valid bytecode and consumes 2 bytes" {
    const instruction = try expectParse(RenderVideoBuffer.parse, &RenderVideoBuffer.Fixtures.valid, 2);

    try testing.expectEqual(.back_buffer, instruction.buffer_id);
}

test "parse returns error.InvalidBufferID on unknown buffer identifier and consumes 2 bytes" {
    try testing.expectError(
        error.InvalidBufferID,
        expectParse(RenderVideoBuffer.parse, &RenderVideoBuffer.Fixtures.invalid_buffer_id, 2),
    );
}

test "execute calls renderVideoBuffer with correct parameters" {
    const instruction = RenderVideoBuffer{
        .buffer_id = .back_buffer,
    };

    const raw_frame_duration = 5;
    const expected_milliseconds = raw_frame_duration * milliseconds_per_frame_unit;

    var machine = mockMachine(struct {
        pub fn renderVideoBuffer(buffer_id: BufferID.Enum, delay: Video.Milliseconds) void {
            testing.expectEqual(.back_buffer, buffer_id) catch unreachable;
            testing.expectEqual(expected_milliseconds, delay) catch unreachable;
        }
    });
    machine.registers.setUnsigned(.frame_duration, raw_frame_duration);
    machine.registers.setUnsigned(.render_video_buffer_UNKNOWN, 1234);

    instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.renderVideoBuffer);

    try testing.expectEqual(0, machine.registers.unsigned(.render_video_buffer_UNKNOWN));
}
