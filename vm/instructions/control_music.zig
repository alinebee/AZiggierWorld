const Opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");
const ResourceID = @import("../types/resource_id.zig");

const print = @import("std").debug.print;

const Delay = u16;
const Offset = u8;

/// Starts, stops or delays the current music track.
pub const Instance = union(enum) {
    /// Begin playing a music track.
    play: struct {
        /// The ID of the music resource to play.
        resource_id: ResourceID.Raw,
        /// The offset within the music resource at which to start playing.
        /// (TODO: document the meaning and units of this value.)
        offset: Offset,
        /// The delay before playing the track.
        /// (TODO: document what units this is in. Tics?)
        delay: Delay,
    },
    /// Override the delay on the current or subsequent `play` instruction.
    set_delay: Delay,
    /// Stop playing any currently-playing music track.
    stop,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        switch (self) {
            .play       => |operation| print("\nControlMusic: play {} at {} after {}\n", .{ operation.resource_id, operation.offset, operation.delay }),
            .set_delay  => |delay| print("\nControlMusic: set delay to {}\n", .{ delay }),
            .stop       => print("\nControlResources: stop playing\n", .{}),
        }
    }
};

pub const Error = Program.Error;

/// Parse the next instruction from a bytecode program.
/// Consumes 5 bytes from the bytecode on success.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const resource_id = try program.read(ResourceID.Raw);
    const delay = try program.read(Delay);
    const offset = try program.read(Offset);

    if (resource_id != 0) {
        return Instance { .play = .{ 
            .resource_id = resource_id,
            .offset = offset,
            .delay = delay,
        } };
    } else if (delay != 0) {
        return Instance { .set_delay = delay };
    } else {
        return .stop;
    }
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.ControlMusic);

    pub const play      = [_]u8 { raw_opcode, 0xDE, 0xAD, 0xBE, 0xEF, 0xFF };
    pub const set_delay = [_]u8 { raw_opcode, 0x00, 0x00, 0xBE, 0xEF, 0xFF };
    pub const stop      = [_]u8 { raw_opcode, 0x00, 0x00, 0x00, 0x00, 0xFF };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const debugParseInstruction = @import("test_helpers.zig").debugParseInstruction;

test "parse parses play instruction and consumes 5 bytes" {
    const instruction = try debugParseInstruction(parse, &BytecodeExamples.play, 5);
    const expected = Instance { .play = .{
        .resource_id = 0xDEAD,
        .offset = 0xFF,
        .delay = 0xBEEF,
    } };
    testing.expectEqual(expected, instruction);
}

test "parse parses set_delay instruction and consumes 5 bytes" {
    const instruction = try debugParseInstruction(parse, &BytecodeExamples.set_delay, 5);
    
    testing.expectEqual(.{ .set_delay = 0xBEEF }, instruction);
}

test "parse parses stop instruction and consumes 5 bytes" {
    const instruction = try debugParseInstruction(parse, &BytecodeExamples.stop, 5);
    
    testing.expectEqual(.stop, instruction);
}

test "execute with play instruction runs on machine without errors" {
    const instruction = Instance { .play = .{
        .resource_id = 0x8BAD,
        .offset = 0x00,
        .delay = 0xF00D,
    } };
    var machine = Machine.new();
    instruction.execute(&machine);
}

test "execute with set_delay instruction runs on machine without errors" {
    const instruction = Instance { .set_delay = 0xF00D };
    var machine = Machine.new();
    instruction.execute(&machine);
}

test "execute with stop instruction runs on machine without errors" {
    const instruction = Instance.stop;
    var machine = Machine.new();
    instruction.execute(&machine);
}
