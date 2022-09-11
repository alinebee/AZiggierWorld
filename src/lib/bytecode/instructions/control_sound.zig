const anotherworld = @import("../../anotherworld.zig");
const resources = anotherworld.resources;
const audio = anotherworld.audio;
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const Program = @import("../program.zig").Program;

/// Play a sound on a channel, or stop a channel from playing.
pub const ControlSound = union(enum) {
    play: struct {
        /// The ID of the sound to play.
        resource_id: resources.ResourceID,
        /// The channel on which to play the sound.
        channel_id: audio.ChannelID,
        /// The volume at which to play the sound.
        /// TODO: document default volume and observed range.
        volume: audio.Volume,
        /// The ID of the preset pitch at which to play the sound.
        frequency_id: audio.FrequencyID,
    },
    stop: audio.ChannelID,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 6 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const raw_resource_id = try program.read(resources.ResourceID.Raw);
        const raw_frequency_id = try program.read(audio.FrequencyID.Raw);
        const raw_volume = try program.read(audio.Volume.Raw);
        const raw_channel_id = try program.read(audio.ChannelID.Raw);

        // Do failable parsing *after* loading all the bytes that this instruction would normally consume;
        // This way, tests that recover from failed parsing will parse the rest of the bytecode correctly.
        const resource_id = resources.ResourceID.cast(raw_resource_id);
        const volume = audio.Volume.cast(raw_volume);
        const frequency_id = try audio.FrequencyID.parse(raw_frequency_id);
        const channel_id = try audio.ChannelID.parse(raw_channel_id);

        if (volume != .zero) {
            return Self{
                .play = .{
                    .resource_id = resource_id,
                    .channel_id = channel_id,
                    .volume = volume,
                    .frequency_id = frequency_id,
                },
            };
        } else {
            // TODO: raise an error if frequency and resource ID were non-zero?
            return Self{ .stop = channel_id };
        }
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *vm.Machine) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) !void {
        switch (self) {
            .play => |operation| try machine.playSound(operation.resource_id, operation.channel_id, operation.volume, operation.frequency_id),
            .stop => |channel_id| machine.stopChannel(channel_id),
        }
    }

    // - Exported constants -

    pub const opcode = Opcode.ControlSound;
    pub const ParseError = Program.ReadError || audio.ChannelID.Error || audio.FrequencyID.Error;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = play;

        const play = [6]u8{ raw_opcode, 0xDE, 0xAD, 0x27, 0x3F, 0x03 };
        const stop = [6]u8{ raw_opcode, 0x00, 0x00, 0x00, 0x00, 0x01 };

        const out_of_range_volume = [6]u8{ raw_opcode, 0xDE, 0xAD, 0x27, 0x40, 0x03 };
        const invalid_frequency_id = [6]u8{ raw_opcode, 0xDE, 0xAD, 0x28, 0x3F, 0x03 };
        const invalid_channel_id = [6]u8{ raw_opcode, 0xDE, 0xAD, 0x27, 0x3F, 0x04 };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = vm.mockMachine;

test "parse parses play instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlSound.parse, &ControlSound.Fixtures.play, 6);
    const expected = ControlSound{
        .play = .{
            .resource_id = resources.ResourceID.cast(0xDEAD),
            .channel_id = audio.ChannelID.cast(3),
            .volume = audio.Volume.cast(63),
            .frequency_id = try audio.FrequencyID.parse(39),
        },
    };
    try testing.expectEqual(expected, instruction);
}

test "parse parses stop instruction and consumes 6 bytes" {
    const instruction = try expectParse(ControlSound.parse, &ControlSound.Fixtures.stop, 6);
    const expected = ControlSound{ .stop = audio.ChannelID.cast(1) };
    try testing.expectEqual(expected, instruction);
}

test "parse returns clamped volume when out of range volume is specified in bytecode" {
    const instruction = try expectParse(ControlSound.parse, &ControlSound.Fixtures.out_of_range_volume, 6);
    const expected = ControlSound{
        .play = .{
            .resource_id = resources.ResourceID.cast(0xDEAD),
            .channel_id = audio.ChannelID.cast(3),
            .volume = audio.Volume.cast(63),
            .frequency_id = try audio.FrequencyID.parse(39),
        },
    };
    try testing.expectEqual(expected, instruction);
}

test "parse returns error.InvalidFrequencyID when out of range frequency is specified in bytecode" {
    try testing.expectError(
        error.InvalidFrequencyID,
        expectParse(ControlSound.parse, &ControlSound.Fixtures.invalid_frequency_id, 6),
    );
}

test "parse returns error.InvalidChannelID when unknown channel is specified in bytecode" {
    try testing.expectError(
        error.InvalidChannelID,
        expectParse(ControlSound.parse, &ControlSound.Fixtures.invalid_channel_id, 6),
    );
}

test "execute with play instruction calls playSound with correct parameters" {
    const instruction = ControlSound{
        .play = .{
            .resource_id = resources.ResourceID.cast(0xDEAD),
            .channel_id = audio.ChannelID.cast(0),
            .volume = audio.Volume.cast(20),
            .frequency_id = try audio.FrequencyID.parse(0),
        },
    };

    var machine = mockMachine(struct {
        pub fn playSound(resource_id: resources.ResourceID, channel_id: audio.ChannelID, volume: audio.Volume, frequency: audio.FrequencyID) !void {
            try testing.expectEqual(resources.ResourceID.cast(0xDEAD), resource_id);
            try testing.expectEqual(audio.ChannelID.cast(0), channel_id);
            try testing.expectEqual(audio.Volume.cast(20), volume);
            try testing.expectEqual(try audio.FrequencyID.parse(0), frequency);
        }

        pub fn stopChannel(_: audio.ChannelID) void {
            unreachable;
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.playSound);
}

test "execute with stop instruction runs on machine without errors" {
    const instruction = ControlSound{ .stop = audio.ChannelID.cast(1) };

    var machine = mockMachine(struct {
        pub fn playSound(_: resources.ResourceID, _: audio.ChannelID, _: audio.Volume, _: audio.FrequencyID) !void {
            unreachable;
        }

        pub fn stopChannel(channel_id: audio.ChannelID) void {
            testing.expectEqual(audio.ChannelID.cast(1), channel_id) catch {
                unreachable;
            };
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.stopChannel);
}
