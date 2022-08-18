const anotherworld = @import("../anotherworld.zig");

const Point = anotherworld.rendering.Point;

const Opcode = @import("opcode.zig").Opcode;
const Program = @import("../../machine/program.zig").Program;
const Machine = @import("../../machine/machine.zig").Machine;
const BufferID = @import("../../values/buffer_id.zig").BufferID;

/// Copies the contents of one video buffer into another.
pub const CopyVideoBuffer = struct {
    /// The buffer to copy from.
    source: BufferID,
    /// The buffer to copy into.
    destination: BufferID,
    /// If true, the source buffer will be copied into the destination buffer
    /// at the current value of the scroll_y_position register, to simulate vertical scrolling.
    /// If false, the source buffer will replace the entire destination buffer at 0 offset.
    use_vertical_offset: bool,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const raw_source = try program.read(BufferID.Raw);
        const raw_destination = try program.read(BufferID.Raw);

        // When copying from a specific buffer, rather than from the front or back buffer,
        // the top bit of the raw source ID in the instruction flags whether to respect (1)
        // or ignore (0) the current vertical scroll offset.
        // This is derived from some squirrely masking logic in the reference implementation:
        // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/30b29209214cbf3d3d179b85a7f2bc47ba4a8730/src/video.cpp#L498

        var sanitised_source: BufferID.Raw = undefined;
        var use_vertical_offset: bool = undefined;

        if (raw_source == BufferID.raw_front_buffer or raw_source == BufferID.raw_back_buffer) {
            sanitised_source = raw_source;
            use_vertical_offset = false;
        } else {
            // Remove the top flag bit(s) from the source to get a sanitised buffer constant.
            // Some instructions in the original bytecode also set the second-highest bit;
            // The meaning of that bit is unknown, and the reference implementation always
            // ignores it and masks it off.
            sanitised_source = raw_source & 0b0011_1111;
            use_vertical_offset = (raw_source & 0b1000_0000) != 0;
        }

        return Self{
            .source = try BufferID.parse(sanitised_source),
            .destination = try BufferID.parse(raw_destination),
            .use_vertical_offset = use_vertical_offset,
        };
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *Machine) void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) void {
        if (self.use_vertical_offset) {
            const offset = machine.registers.signed(.scroll_y_position);
            machine.copyVideoBuffer(self.source, self.destination, offset);
        } else {
            machine.copyVideoBuffer(self.source, self.destination, 0);
        }
    }

    // - Exported constants -
    pub const opcode = Opcode.CopyVideoBuffer;

    pub const ParseError = Program.ReadError || BufferID.Error;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = specific_buffer_ignore_offset;

        const specific_buffer_ignore_offset = [3]u8{ raw_opcode, 0b0100_0011, 0x01 };
        const specific_buffer_respect_offset = [3]u8{ raw_opcode, 0b1100_0011, 0x01 };
        const front_buffer = [3]u8{ raw_opcode, 0xFE, 0x01 };
        const back_buffer = [3]u8{ raw_opcode, 0xFF, 0x01 };

        const invalid_source = [3]u8{ raw_opcode, 0b1000_1111, 0x01 };
        const invalid_destination = [3]u8{ raw_opcode, 0x00, 0x8B };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = @import("../../machine/test_helpers/mock_machine.zig").mockMachine;

test "parse parses valid bytecode without vertical offset flag and consumes 3 bytes" {
    const instruction = try expectParse(CopyVideoBuffer.parse, &CopyVideoBuffer.Fixtures.specific_buffer_ignore_offset, 3);

    try testing.expectEqual(.{ .specific = 3 }, instruction.source);
    try testing.expectEqual(.{ .specific = 1 }, instruction.destination);
    try testing.expectEqual(false, instruction.use_vertical_offset);
}

test "parse parses valid bytecode with vertical offset flag and consumes 3 bytes" {
    const instruction = try expectParse(CopyVideoBuffer.parse, &CopyVideoBuffer.Fixtures.specific_buffer_respect_offset, 3);

    try testing.expectEqual(.{ .specific = 3 }, instruction.source);
    try testing.expectEqual(.{ .specific = 1 }, instruction.destination);
    try testing.expectEqual(true, instruction.use_vertical_offset);
}

test "parse parses valid bytecode with front buffer source and consumes 3 bytes" {
    const instruction = try expectParse(CopyVideoBuffer.parse, &CopyVideoBuffer.Fixtures.front_buffer, 3);

    try testing.expectEqual(.front_buffer, instruction.source);
    try testing.expectEqual(.{ .specific = 1 }, instruction.destination);
    try testing.expectEqual(false, instruction.use_vertical_offset);
}

test "parse parses valid bytecode with back buffer source and consumes 3 bytes" {
    const instruction = try expectParse(CopyVideoBuffer.parse, &CopyVideoBuffer.Fixtures.back_buffer, 3);

    try testing.expectEqual(.back_buffer, instruction.source);
    try testing.expectEqual(.{ .specific = 1 }, instruction.destination);
    try testing.expectEqual(false, instruction.use_vertical_offset);
}

test "parse returns error.InvalidBufferID on unknown source and consumes 3 bytes" {
    try testing.expectError(
        error.InvalidBufferID,
        expectParse(CopyVideoBuffer.parse, &CopyVideoBuffer.Fixtures.invalid_source, 3),
    );
}

test "parse returns error.InvalidBufferID on unknown destination and consumes 3 bytes" {
    try testing.expectError(
        error.InvalidBufferID,
        expectParse(CopyVideoBuffer.parse, &CopyVideoBuffer.Fixtures.invalid_destination, 3),
    );
}

test "execute calls copyVideoBuffer with offset when use_vertical_offset = true" {
    const instruction = CopyVideoBuffer{
        .source = .front_buffer,
        .destination = .back_buffer,
        .use_vertical_offset = true,
    };

    var machine = mockMachine(struct {
        pub fn copyVideoBuffer(source: BufferID, destination: BufferID, vertical_offset: Point.Coordinate) void {
            testing.expectEqual(.front_buffer, source) catch {
                unreachable;
            };
            testing.expectEqual(.back_buffer, destination) catch {
                unreachable;
            };
            testing.expectEqual(199, vertical_offset) catch {
                unreachable;
            };
        }
    });
    machine.registers.setSigned(.scroll_y_position, 199);

    instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.copyVideoBuffer);
}

test "execute ignores vertical offset when use_vertical_offset = false" {
    const instruction = CopyVideoBuffer{
        .source = .front_buffer,
        .destination = .back_buffer,
        .use_vertical_offset = false,
    };

    var machine = mockMachine(struct {
        pub fn copyVideoBuffer(source: BufferID, destination: BufferID, vertical_offset: Point.Coordinate) void {
            testing.expectEqual(.front_buffer, source) catch {
                unreachable;
            };
            testing.expectEqual(.back_buffer, destination) catch {
                unreachable;
            };
            testing.expectEqual(0, vertical_offset) catch {
                unreachable;
            };
        }
    });
    machine.registers.setSigned(.scroll_y_position, 199);

    instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.copyVideoBuffer);
}
