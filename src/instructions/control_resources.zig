const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const ResourceID = @import("../values/resource_id.zig");
const GamePart = @import("../values/game_part.zig");

/// Loads individual resources or entire game parts into memory.
pub const Instance = union(enum) {
    /// Unload all loaded resources and stop audio.
    unload_all,

    /// Load all resources for the specified game part and begin executing its program.
    start_game_part: GamePart.Enum,

    /// Load the specified resource individually.
    load_resource: ResourceID.Raw,

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Instance, machine: *Machine.Instance) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) !void {
        switch (self) {
            .unload_all => machine.unloadAllResources(),
            .start_game_part => |game_part| machine.scheduleGamePart(game_part),
            .load_resource => |resource_id| try machine.loadResource(resource_id),
        }
    }
};

pub const Error = Program.Error;

/// Parse the next instruction from a bytecode program.
/// Consumes 3 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const resource_id_or_game_part = try program.read(ResourceID.Raw);

    if (resource_id_or_game_part == 0) {
        return .unload_all;
    } else if (GamePart.parse(resource_id_or_game_part)) |game_part| {
        return Instance{ .start_game_part = game_part };
    } else |_| {
        // If the value doesn't match any game part, assume it's a resource ID
        return Instance{ .load_resource = resource_id_or_game_part };
    }
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.ControlResources);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = start_game_part;

    const unload_all = [3]u8{ raw_opcode, 0x0, 0x0 };
    const start_game_part = [3]u8{ raw_opcode, 0x3E, 0x85 }; // GamePart.Enum.arena_cinematic
    const load_resource = [3]u8{ raw_opcode, 0xDE, 0xAD };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("test_helpers/mock_machine.zig");

test "parse parses unload_all instruction and consumes 3 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.unload_all, 3);

    try testing.expectEqual(.unload_all, instruction);
}

test "parse parses start_game_part instruction and consumes 3 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.start_game_part, 3);

    try testing.expectEqual(.{ .start_game_part = .arena_cinematic }, instruction);
}

test "parse parses load_resource instruction and consumes 3 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.load_resource, 3);

    try testing.expectEqual(.{ .load_resource = 0xDEAD }, instruction);
}

test "execute with unload_all instruction calls unloadAllResources with correct parameters" {
    const instruction: Instance = .unload_all;

    var machine = MockMachine.new(struct {
        pub fn scheduleGamePart(_: GamePart.Enum) void {
            unreachable;
        }

        pub fn loadResource(_: ResourceID.Raw) !void {
            unreachable;
        }

        pub fn unloadAllResources() void {}
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.unloadAllResources);
}

test "execute with start_game_part instruction calls scheduleGamePart with correct parameters" {
    const instruction = Instance{ .start_game_part = .arena_cinematic };

    var machine = MockMachine.new(struct {
        pub fn scheduleGamePart(game_part: GamePart.Enum) void {
            testing.expectEqual(.arena_cinematic, game_part) catch unreachable;
        }

        pub fn loadResource(_: ResourceID.Raw) !void {
            unreachable;
        }

        pub fn unloadAllResources() void {
            unreachable;
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.scheduleGamePart);
}

test "execute with load_resource instruction calls loadResource with correct parameters" {
    const instruction = Instance{ .load_resource = 0xBEEF };

    var machine = MockMachine.new(struct {
        pub fn scheduleGamePart(_: GamePart.Enum) void {
            unreachable;
        }

        pub fn loadResource(resource_id: ResourceID.Raw) !void {
            try testing.expectEqual(0xBEEF, resource_id);
        }

        pub fn unloadAllResources() void {
            unreachable;
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.loadResource);
}
