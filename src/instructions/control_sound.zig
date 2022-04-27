const Opcode = @import("../values/opcode.zig").Opcode;
const Program = @import("../machine/program.zig").Program;
const Machine = @import("../machine/machine.zig").Machine;
const Audio = @import("../machine/audio.zig").Audio;

const ResourceID = @import("../values/resource_id.zig");
const Channel = @import("../values/channel.zig");

/// Play a sound on a channel, or stop a channel from playing.
pub const ControlSound = union(enum) {
    play: struct {
        /// The ID of the sound to play.
        resource_id: ResourceID.Raw,
        /// The channel on which to play the sound.
        channel: Channel.Trusted,
        /// The volume at which to play the sound.
        /// TODO: document default volume and observed range.
        volume: Audio.Volume,
        /// The pitch at which to play the sound.
        /// TODO: document default frequency and observed range.
        frequency: Audio.Frequency,
    },
    stop: Channel.Trusted,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 6 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const resource_id = try program.read(ResourceID.Raw);
        const frequency = try program.read(Audio.Frequency);
        const volume = try program.read(Audio.Volume);
        const channel = try Channel.parse(try program.read(Channel.Raw));

        if (volume > 0) {
            return Self{
                .play = .{
                    .resource_id = resource_id,
                    .channel = channel,
                    .volume = volume,
                    .frequency = frequency,
                },
            };
        } else {
            return Self{ .stop = channel };
        }
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *Machine) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) !void {
        switch (self) {
            .play => |operation| try machine.playSound(operation.resource_id, operation.channel, operation.volume, operation.frequency),
            .stop => |channel| machine.stopChannel(channel),
        }
    }

    // - Exported constants -

    pub const opcode = Opcode.ControlSound;
    pub const ParseError = Program.ReadError || Channel.Error;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = @enumToInt(opcode);

        /// Example bytecode that should produce a valid instruction.
        pub const valid = play;

        const play = [6]u8{ raw_opcode, 0xDE, 0xAD, 0xBE, 0xEF, 0x03 };
        const stop = [6]u8{ raw_opcode, 0x00, 0x00, 0x00, 0x00, 0x01 };

        const invalid_channel = [6]u8{ raw_opcode, 0xDE, 0xAD, 0xFF, 0x80, 0x04 };
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = @import("../machine/test_helpers/mock_machine.zig").mockMachine;

test "parse parses play instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlSound.parse, &ControlSound.Fixtures.play, 6);
    const expected = ControlSound{
        .play = .{
            .resource_id = 0xDEAD,
            .channel = 3,
            .volume = 0xEF,
            .frequency = 0xBE,
        },
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses stop instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlSound.parse, &ControlSound.Fixtures.stop, 6);
    const expected = ControlSound{ .stop = 1 };
    try testing.expectEqual(expected, instruction);
}

test "parse returns error.InvalidChannel when unknown channel is specified in bytecode" {
    try testing.expectError(
        error.InvalidChannel,
        expectParse(ControlSound.parse, &ControlSound.Fixtures.invalid_channel, 6),
    );
}

test "execute with play instruction calls playSound with correct parameters" {
    const instruction = ControlSound{
        .play = .{
            .resource_id = 0xDEAD,
            .channel = 0,
            .volume = 20,
            .frequency = 0,
        },
    };

    var machine = mockMachine(struct {
        pub fn playSound(resource_id: ResourceID.Raw, channel: Channel.Trusted, volume: Audio.Volume, frequency: Audio.Frequency) !void {
            try testing.expectEqual(0xDEAD, resource_id);
            try testing.expectEqual(0, channel);
            try testing.expectEqual(20, volume);
            try testing.expectEqual(0, frequency);
        }

        pub fn stopChannel(_: Channel.Trusted) void {
            unreachable;
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.playSound);
}

test "execute with stop instruction runs on machine without errors" {
    const instruction = ControlSound{ .stop = 1 };

    var machine = mockMachine(struct {
        pub fn playSound(_: ResourceID.Raw, _: Channel.Trusted, _: Audio.Volume, _: Audio.Frequency) !void {
            unreachable;
        }

        pub fn stopChannel(channel: Channel.Trusted) void {
            testing.expectEqual(1, channel) catch {
                unreachable;
            };
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.stopChannel);
}
