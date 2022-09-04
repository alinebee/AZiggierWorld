const anotherworld = @import("../../anotherworld.zig");
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const Program = @import("../program.zig").Program;
const Machine = vm.Machine;
const BufferID = vm.BufferID;

/// Renders the contents of a video buffer to the host screen,
/// leaving the previous frame on-screen for a variable duration before
/// replacing it with the new one.
pub const RenderVideoBuffer = struct {
    /// The buffer to render.
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
        // The delay to leave the previous frame visible is expressed
        // as a number of PAL frames,  where each frame is 20ms.
        // In Another World's original bytecode, the delay is typically
        // 1-11 frames (20-220 ms).
        const delay_in_frames = machine.registers.unsigned(.frame_duration);

        // Copypasta from reference implementation.
        // From examining Another World's bytecode, nothing else ever writes to this register;
        // since 0 is the initial value of all registers, this code effectively does nothing.
        // Some instructions do read from this register, so altering this value at compile time
        // may have some effect.
        machine.registers.setUnsigned(.render_video_buffer_UNKNOWN, 0);

        machine.renderVideoBuffer(self.buffer_id, delay_in_frames);
    }

    // - Exported constants -
    pub const ParseError = Program.ReadError || BufferID.Error;
    pub const opcode = Opcode.RenderVideoBuffer;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [2]u8{ raw_opcode, 0xFF };

        const invalid_buffer_id = [2]u8{ raw_opcode, 0x8B };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = vm.mockMachine;

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

    var machine = mockMachine(struct {
        pub fn renderVideoBuffer(buffer_id: BufferID, delay_in_frames: vm.FrameCount) void {
            testing.expectEqual(.back_buffer, buffer_id) catch unreachable;
            testing.expectEqual(5, delay_in_frames) catch unreachable;
        }
    });
    machine.registers.setUnsigned(.frame_duration, raw_frame_duration);
    machine.registers.setUnsigned(.render_video_buffer_UNKNOWN, 1234);

    instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.renderVideoBuffer);

    try testing.expectEqual(0, machine.registers.unsigned(.render_video_buffer_UNKNOWN));
}
