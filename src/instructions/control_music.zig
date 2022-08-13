const Opcode = @import("../values/opcode.zig").Opcode;
const Program = @import("../machine/program.zig").Program;
const Machine = @import("../machine/machine.zig").Machine;
const Audio = @import("../machine/audio.zig").Audio;
const ResourceID = @import("../values/resource_id.zig").ResourceID;

/// Starts, stops or delays the current music track.
pub const ControlMusic = union(enum) {
    /// Begin playing a music track.
    play: struct {
        /// The ID of the music resource to play.
        resource_id: ResourceID,
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

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 6 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const possible_resource_id = try program.read(ResourceID.Raw);
        const delay = try program.read(Audio.Delay);
        const offset = try program.read(Audio.Offset);

        const no_resource_id = 0;
        const no_delay = 0;

        if (possible_resource_id != no_resource_id) {
            return Self{
                .play = .{
                    .resource_id = ResourceID.cast(possible_resource_id),
                    .offset = offset,
                    .delay = delay,
                },
            };
        } else if (delay != no_delay) {
            return Self{ .set_delay = delay };
        } else {
            return .stop;
        }
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *Machine) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) !void {
        switch (self) {
            .play => |operation| try machine.playMusic(operation.resource_id, operation.offset, operation.delay),
            .set_delay => |delay| machine.setMusicDelay(delay),
            .stop => machine.stopMusic(),
        }
    }

    // - Exported constants -

    pub const opcode = Opcode.ControlMusic;
    pub const ParseError = Program.ReadError;

    // -- Bytecode examples --

    // zig fmt: off
    pub const Fixtures = struct {
        const raw_opcode = @enumToInt(opcode);

        /// Example bytecode that should produce a valid instruction.
        pub const valid = play;

        const play      = [6]u8{ raw_opcode, 0xDE, 0xAD, 0xBE, 0xEF, 0xFF };
        const set_delay = [6]u8{ raw_opcode, 0x00, 0x00, 0xBE, 0xEF, 0xFF };
        const stop      = [6]u8{ raw_opcode, 0x00, 0x00, 0x00, 0x00, 0xFF };
    };
    // zig fmt: on
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = @import("../machine/test_helpers/mock_machine.zig").mockMachine;

test "parse parses play instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlMusic.parse, &ControlMusic.Fixtures.play, 6);
    const expected = ControlMusic{
        .play = .{
            .resource_id = ResourceID.cast(0xDEAD),
            .offset = 0xFF,
            .delay = 0xBEEF,
        },
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses set_delay instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlMusic.parse, &ControlMusic.Fixtures.set_delay, 6);

    try testing.expectEqual(.{ .set_delay = 0xBEEF }, instruction);
}

test "parse parses stop instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlMusic.parse, &ControlMusic.Fixtures.stop, 6);

    try testing.expectEqual(.stop, instruction);
}

test "execute with play instruction calls playMusic with correct parameters" {
    const instruction: ControlMusic = .{
        .play = .{
            .resource_id = ResourceID.cast(0x8BAD),
            .offset = 0x12,
            .delay = 0xF00D,
        },
    };

    var machine = mockMachine(struct {
        pub fn playMusic(resource_id: ResourceID, offset: Audio.Offset, delay: Audio.Delay) !void {
            try testing.expectEqual(ResourceID.cast(0x8BAD), resource_id);
            try testing.expectEqual(0x12, offset);
            try testing.expectEqual(0xF00D, delay);
        }

        pub fn setMusicDelay(_: Audio.Delay) void {
            unreachable;
        }

        pub fn stopMusic() void {
            unreachable;
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.playMusic);
}

test "execute with set_delay instruction calls setMusicDelay with correct parameters" {
    const instruction: ControlMusic = .{ .set_delay = 0xF00D };

    var machine = mockMachine(struct {
        pub fn playMusic(_: ResourceID, _: Audio.Offset, _: Audio.Delay) !void {
            unreachable;
        }

        pub fn setMusicDelay(delay: Audio.Delay) void {
            testing.expectEqual(0xF00D, delay) catch {
                unreachable;
            };
        }

        pub fn stopMusic() void {
            unreachable;
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.setMusicDelay);
}

test "execute with stop instruction calls stopMusic with correct parameters" {
    const instruction: ControlMusic = .stop;

    var machine = mockMachine(struct {
        pub fn playMusic(_: ResourceID, _: Audio.Offset, _: Audio.Delay) !void {
            unreachable;
        }

        pub fn setMusicDelay(_: Audio.Delay) void {
            unreachable;
        }

        pub fn stopMusic() void {}
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.stopMusic);
}
