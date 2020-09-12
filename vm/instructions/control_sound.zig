const Opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");

const ResourceID = @import("../types/resource_id.zig");
const Channel = @import("../types/channel.zig");

const print = @import("std").debug.print;

pub const Volume = u8;
pub const Frequency = u8;

/// Play a sound on a channel, or stop a channel from playing.
pub const Instance = union(enum) {
    play: struct {
        /// The ID of the sound to play.
        resource_id: ResourceID.Raw,
        /// The channel on which to play the sound.
        channel: Channel.Enum,
        /// The volume at which to play the sound.
        /// TODO: document default volume and observed range.
        volume: Volume,
        /// The pitch at which to play the sound.
        /// TODO: document default frequency and observed range.
        frequency: Frequency,
    },
    stop: Channel.Enum,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        switch (self) {
            .play => |operation| print("\nControlSound: play #{X} on channel {} at volume {}, frequency {}\n", .{ 
                operation.resource_id,
                @tagName(operation.channel),
                operation.volume,
                operation.frequency,
            }),
            .stop => |channel| print("\nControlResources: stop playing on channel {}\n", .{ @tagName(channel) }),
        }
    }
};

pub const Error = Program.Error || Channel.Error;

/// Parse the next instruction from a bytecode program.
/// Consumes 5 bytes from the bytecode on success.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const resource_id = try program.read(ResourceID.Raw);
    const frequency = try program.read(Frequency);
    const volume = try program.read(Volume);
    const channel = try Channel.parse(try program.read(Channel.Raw));
    
    if (volume > 0) {
        return Instance { .play = .{
            .resource_id = resource_id,
            .channel = channel,
            .volume = volume,
            .frequency = frequency,
        } };
    } else {
        return Instance { .stop = channel };
    }
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.ControlSound);

    pub const play = [_]u8 { raw_opcode, 0xDE, 0xAD, 0xBE, 0xEF, 0x03 };
    pub const stop = [_]u8 { raw_opcode, 0x00, 0x00, 0x00, 0x00, 0x01 };
    
    pub const invalid_channel = [_]u8 { raw_opcode, 0xDE, 0xAD, 0xFF, 0x80, 0x04 };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const debugParseInstruction = @import("test_helpers.zig").debugParseInstruction;

test "parse parses play instruction and consumes 5 bytes" {
    const instruction = try debugParseInstruction(parse, &BytecodeExamples.play, 5);
    const expected = Instance { .play = .{
        .resource_id = 0xDEAD,
        .channel = .four,
        .volume = 0xEF,
        .frequency = 0xBE,
    } };
    testing.expectEqual(expected, instruction);
}

test "parse parses stop instruction and consumes 5 bytes" {
    const instruction = try debugParseInstruction(parse, &BytecodeExamples.stop, 5);
    const expected = Instance { .stop = .two };
    testing.expectEqual(expected, instruction);
}

test "parse returns error.InvalidChannel when unknown channel is specified in bytecode" {
    testing.expectError(
        error.InvalidChannel,
        debugParseInstruction(parse, &BytecodeExamples.invalid_channel, 5),
    );
}

// TODO: flesh these tests out once we have sound playback implemented in the VM
test "execute with play instruction runs on machine without errors" {
    const instruction = Instance { .play = .{
        .resource_id = 0xDEAD,
        .channel = .one,
        .volume = 20,
        .frequency = 0,
    } };

    var machine = Machine.new();
    instruction.execute(&machine);
}

test "execute with stop instruction runs on machine without errors" {
    const instruction = Instance { .stop = .two };

    var machine = Machine.new();
    instruction.execute(&machine);
}