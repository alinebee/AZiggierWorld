const Opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");
const Audio = @import("../audio.zig");
const ResourceID = @import("../types/resource_id.zig");

/// Starts, stops or delays the current music track.
pub const Instance = union(enum) {
    /// Begin playing a music track.
    play: struct {
        /// The ID of the music resource to play.
        resource_id: ResourceID.Raw,
        /// The offset within the music resource at which to start playing.
        /// (TODO: document the meaning and units of this value.)
        offset: Audio.Offset,
        /// The delay before playing the track.
        /// (TODO: document what units this is in. Tics?)
        delay: Audio.Delay,
    },
    /// Override the delay on the current or subsequent `play` instruction.
    set_delay: Audio.Delay,
    /// Stop playing any currently-playing music track.
    stop,

    pub fn execute(self: Instance, machine: *Machine.Instance) !void {
        switch (self) {
            .play       => |operation| try machine.playMusic(operation.resource_id, operation.offset, operation.delay),
            .set_delay  => |delay| machine.setMusicDelay(delay),
            .stop       => machine.stopMusic(),
        }
    }
};

pub const Error = Program.Error;

/// Parse the next instruction from a bytecode program.
/// Consumes 5 bytes from the bytecode on success.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const resource_id = try program.read(ResourceID.Raw);
    const delay = try program.read(Audio.Delay);
    const offset = try program.read(Audio.Offset);

    if (resource_id != 0) {
        return Instance{
            .play = .{
                .resource_id = resource_id,
                .offset = offset,
                .delay = delay,
            },
        };
    } else if (delay != 0) {
        return Instance{ .set_delay = delay };
    } else {
        return .stop;
    }
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.ControlMusic);

    pub const play      = [_]u8{ raw_opcode, 0xDE, 0xAD, 0xBE, 0xEF, 0xFF };
    pub const set_delay = [_]u8{ raw_opcode, 0x00, 0x00, 0xBE, 0xEF, 0xFF };
    pub const stop      = [_]u8{ raw_opcode, 0x00, 0x00, 0x00, 0x00, 0xFF };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses play instruction and consumes 5 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.play, 5);
    const expected = Instance{
        .play = .{
            .resource_id = 0xDEAD,
            .offset = 0xFF,
            .delay = 0xBEEF,
        },
    };
    testing.expectEqual(expected, instruction);
}

test "parse parses set_delay instruction and consumes 5 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.set_delay, 5);

    testing.expectEqual(.{ .set_delay = 0xBEEF }, instruction);
}

test "parse parses stop instruction and consumes 5 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.stop, 5);

    testing.expectEqual(.stop, instruction);
}

// TODO: flesh these tests out once we have music playback implemented in the VM
test "execute with play instruction runs on machine without errors" {
    const instruction = Instance{
        .play = .{
            .resource_id = 0x8BAD,
            .offset = 0x00,
            .delay = 0xF00D,
        },
    };
    var machine = Machine.new();
    try instruction.execute(&machine);
}

test "execute with set_delay instruction runs on machine without errors" {
    const instruction = Instance{ .set_delay = 0xF00D };
    var machine = Machine.new();
    try instruction.execute(&machine);
}

test "execute with stop instruction runs on machine without errors" {
    const instruction = Instance.stop;
    var machine = Machine.new();
    try instruction.execute(&machine);
}
