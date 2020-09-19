const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const Audio = @import("../machine/audio.zig");

const ResourceID = @import("../values/resource_id.zig");
const Channel = @import("../values/channel.zig");

/// Play a sound on a channel, or stop a channel from playing.
pub const Instance = union(enum) {
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

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Instance, machine: *Machine.Instance) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) !void {
        switch (self) {
            .play => |operation| try machine.playSound(operation.resource_id, operation.channel, operation.volume, operation.frequency),
            .stop => |channel| machine.stopChannel(channel),
        }
    }
};

pub const Error = Program.Error || Channel.Error;

/// Parse the next instruction from a bytecode program.
/// Consumes 6 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const resource_id = try program.read(ResourceID.Raw);
    const frequency = try program.read(Audio.Frequency);
    const volume = try program.read(Audio.Volume);
    const channel = try Channel.parse(try program.read(Channel.Raw));

    if (volume > 0) {
        return Instance{
            .play = .{
                .resource_id = resource_id,
                .channel = channel,
                .volume = volume,
                .frequency = frequency,
            },
        };
    } else {
        return Instance{ .stop = channel };
    }
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.ControlSound);

    pub const play = [6]u8{ raw_opcode, 0xDE, 0xAD, 0xBE, 0xEF, 0x03 };
    pub const stop = [6]u8{ raw_opcode, 0x00, 0x00, 0x00, 0x00, 0x01 };

    pub const invalid_channel = [6]u8{ raw_opcode, 0xDE, 0xAD, 0xFF, 0x80, 0x04 };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("test_helpers/mock_machine.zig");

test "parse parses play instruction and consumes 6 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.play, 6);
    const expected = Instance{
        .play = .{
            .resource_id = 0xDEAD,
            .channel = 3,
            .volume = 0xEF,
            .frequency = 0xBE,
        },
    };
    testing.expectEqual(expected, instruction);
}

test "parse parses stop instruction and consumes 6 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.stop, 6);
    const expected = Instance{ .stop = 1 };
    testing.expectEqual(expected, instruction);
}

test "parse returns error.InvalidChannel when unknown channel is specified in bytecode" {
    testing.expectError(
        error.InvalidChannel,
        expectParse(parse, &BytecodeExamples.invalid_channel, 6),
    );
}

test "execute with play instruction calls playSound with correct parameters" {
    const instruction = Instance{
        .play = .{
            .resource_id = 0xDEAD,
            .channel = 0,
            .volume = 20,
            .frequency = 0,
        },
    };

    var machine = MockMachine.new(struct {
        pub fn playSound(resource_id: ResourceID.Raw, channel: Channel.Trusted, volume: Audio.Volume, frequency: Audio.Frequency) !void {
            testing.expectEqual(0xDEAD, resource_id);
            testing.expectEqual(0, channel);
            testing.expectEqual(20, volume);
            testing.expectEqual(0, frequency);
        }

        pub fn stopChannel(channel: Channel.Trusted) void {
            unreachable;
        }
    });

    try instruction._execute(&machine);
    testing.expectEqual(1, machine.call_counts.playSound);
}

test "execute with stop instruction runs on machine without errors" {
    const instruction = Instance{ .stop = 1 };

    var machine = MockMachine.new(struct {
        pub fn playSound(resource_id: ResourceID.Raw, channel: Channel.Trusted, volume: Audio.Volume, frequency: Audio.Frequency) !void {
            unreachable;
        }

        pub fn stopChannel(channel: Channel.Trusted) void {
            testing.expectEqual(1, channel);
        }
    });

    try instruction._execute(&machine);
    testing.expectEqual(1, machine.call_counts.stopChannel);
}
