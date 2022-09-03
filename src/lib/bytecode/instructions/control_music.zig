const anotherworld = @import("../../anotherworld.zig");
const resources = anotherworld.resources;
const vm = anotherworld.vm;
const audio = anotherworld.audio;

const Opcode = @import("../opcode.zig").Opcode;
const Program = @import("../program.zig").Program;

/// Starts, stops or adjusts the tempo of the current music track.
pub const ControlMusic = union(enum) {
    /// Begin playing a music track.
    play: struct {
        /// The ID of the music resource to play.
        resource_id: resources.ResourceID,
        /// The offset within the music resource at which to start playing.
        offset: audio.Offset,
        /// An optional custom tempo to play the track at.
        /// If specified, this will override the track's default tempo.
        tempo: ?audio.Tempo,
    },
    /// Override the tempo on the current or subsequent `play` instruction.
    set_tempo: audio.Tempo,
    /// Stop playing any currently-playing music track.
    stop,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 6 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const possible_resource_id = try program.read(resources.ResourceID.Raw);
        const tempo = try program.read(audio.Tempo);
        const offset = try program.read(audio.Offset);

        const no_resource_id = 0;
        const no_tempo = 0;

        if (possible_resource_id != no_resource_id) {
            return Self{
                .play = .{
                    .resource_id = resources.ResourceID.cast(possible_resource_id),
                    .offset = offset,
                    .tempo = if (tempo != no_tempo) tempo else null,
                },
            };
        } else if (tempo != no_tempo) {
            return Self{ .set_tempo = tempo };
        } else {
            return .stop;
        }
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *vm.Machine) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) !void {
        switch (self) {
            .play => |operation| try machine.playMusic(operation.resource_id, operation.offset, operation.tempo),
            .set_tempo => |tempo| machine.setMusicTempo(tempo),
            .stop => machine.stopMusic(),
        }
    }

    // - Exported constants -

    pub const opcode = Opcode.ControlMusic;
    pub const ParseError = Program.ReadError;

    // -- Bytecode examples --

    // zig fmt: off
    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = play;

        const play      = [6]u8{ raw_opcode, 0xDE, 0xAD, 0xBE, 0xEF, 0xFF };
        const set_tempo = [6]u8{ raw_opcode, 0x00, 0x00, 0xBE, 0xEF, 0xFF };
        const stop      = [6]u8{ raw_opcode, 0x00, 0x00, 0x00, 0x00, 0xFF };
    };
    // zig fmt: on
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = vm.mockMachine;

test "parse parses play instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlMusic.parse, &ControlMusic.Fixtures.play, 6);
    const expected = ControlMusic{
        .play = .{
            .resource_id = resources.ResourceID.cast(0xDEAD),
            .offset = 0xFF,
            .tempo = 0xBEEF,
        },
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses set_tempo instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlMusic.parse, &ControlMusic.Fixtures.set_tempo, 6);

    try testing.expectEqual(.{ .set_tempo = 0xBEEF }, instruction);
}

test "parse parses stop instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlMusic.parse, &ControlMusic.Fixtures.stop, 6);

    try testing.expectEqual(.stop, instruction);
}

test "execute with play instruction calls playMusic with correct parameters" {
    const instruction: ControlMusic = .{
        .play = .{
            .resource_id = resources.ResourceID.cast(0x8BAD),
            .offset = 0x12,
            .tempo = 0xF00D,
        },
    };

    var machine = mockMachine(struct {
        pub fn playMusic(resource_id: resources.ResourceID, offset: audio.Offset, tempo: ?audio.Tempo) !void {
            try testing.expectEqual(resources.ResourceID.cast(0x8BAD), resource_id);
            try testing.expectEqual(0x12, offset);
            try testing.expectEqual(0xF00D, tempo);
        }

        pub fn setMusicTempo(_: audio.Tempo) void {
            unreachable;
        }

        pub fn stopMusic() void {
            unreachable;
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.playMusic);
}

test "execute with set_tempo instruction calls setMusicTempo with correct parameters" {
    const instruction: ControlMusic = .{ .set_tempo = 0xF00D };

    var machine = mockMachine(struct {
        pub fn playMusic(_: resources.ResourceID, _: audio.Offset, _: ?audio.Tempo) !void {
            unreachable;
        }

        pub fn setMusicTempo(tempo: audio.Tempo) void {
            testing.expectEqual(0xF00D, tempo) catch {
                unreachable;
            };
        }

        pub fn stopMusic() void {
            unreachable;
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.setMusicTempo);
}

test "execute with stop instruction calls stopMusic with correct parameters" {
    const instruction: ControlMusic = .stop;

    var machine = mockMachine(struct {
        pub fn playMusic(_: resources.ResourceID, _: audio.Offset, _: ?audio.Tempo) !void {
            unreachable;
        }

        pub fn setMusicTempo(_: audio.Tempo) void {
            unreachable;
        }

        pub fn stopMusic() void {}
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.stopMusic);
}
