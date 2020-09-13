const Opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");
const ResourceID = @import("../types/resource_id.zig");
const GamePart = @import("../types/game_part.zig");
const Resources = @import("../types/resources.zig");

/// Loads individual resources or entire game parts into memory.
pub const Instance = union(enum) {
    /// Unload all loaded resources and stop audio.
    unload_all,

    /// Load all resources for the specified game part and begin executing its program.
    start_game_part: GamePart.Enum,

    /// Load the specified resource individually.
    load_resource: ResourceID.Raw,

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub inline fn execute(self: Instance, machine: *Machine.Instance) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) !void {
        switch (self) {
            .unload_all => machine.unloadAllResources(),
            .start_game_part => |game_part| try machine.startGamePart(game_part),
            .load_resource => |resource_id| try machine.loadResource(resource_id),
        }
    }
};

pub const Error = Program.Error;

/// Parse the next instruction from a bytecode program.
/// Consumes 2 bytes from the bytecode on success.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const resource_id_or_game_part = try program.read(ResourceID.Raw);

    if (resource_id_or_game_part == 0) {
        return .unload_all;
    } else if (GamePart.parse(resource_id_or_game_part)) |game_part| {
        return Instance{ .start_game_part = game_part };
    } else |_err| {
        // If the value doesn't match any game part, assume it's a resource ID
        return Instance{ .load_resource = resource_id_or_game_part };
    }
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.ControlResources);

    pub const unload_all = [_]u8{ raw_opcode, 0x0, 0x0 };
    pub const start_game_part = [_]u8{ raw_opcode, 0x3E, 0x85 }; // GamePart.Enum.arena_cinematic
    pub const load_resource = [_]u8{ raw_opcode, 0xDE, 0xAD };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("test_helpers/mock_machine.zig");

test "parse parses unload_all instruction and consumes 2 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.unload_all, 2);

    testing.expectEqual(.unload_all, instruction);
}

test "parse parses start_game_part instruction and consumes 2 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.start_game_part, 2);

    testing.expectEqual(.{ .start_game_part = .arena_cinematic }, instruction);
}

test "parse parses load_resource instruction and consumes 2 bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.load_resource, 2);

    testing.expectEqual(.{ .load_resource = 0xDEAD }, instruction);
}

test "execute with unload_all instruction calls unloadAllResources with correct parameters" {
    const instruction = Instance.unload_all;

    const Stubs = struct {
        var call_count: usize = 0;

        pub fn startGamePart(game_part: GamePart.Enum) !void {
            unreachable;
        }

        pub fn loadResource(resource_id: ResourceID.Raw) !void {
            unreachable;
        }

        pub fn unloadAllResources() void {
            call_count += 1;
        }
    };

    var machine = MockMachine.new(Stubs);
    try instruction._execute(&machine);
    testing.expectEqual(1, Stubs.call_count);
}

test "execute with start_game_part instruction calls startGamePart with correct parameters" {
    const instruction = Instance{ .start_game_part = .arena_cinematic };

    const Stubs = struct {
        var call_count: usize = 0;

        pub fn startGamePart(game_part: GamePart.Enum) !void {
            call_count += 1;
            testing.expectEqual(.arena_cinematic, game_part);
        }

        pub fn loadResource(resource_id: ResourceID.Raw) !void {
            unreachable;
        }

        pub fn unloadAllResources() void {
            unreachable;
        }
    };

    var machine = MockMachine.new(Stubs);
    try instruction._execute(&machine);
    testing.expectEqual(1, Stubs.call_count);
}

test "execute with load_resource instruction calls loadResource with correct parameters" {
    const instruction = Instance{ .load_resource = 0xBEEF };

    const Stubs = struct {
        var call_count: usize = 0;

        pub fn startGamePart(game_part: GamePart.Enum) !void {
            unreachable;
        }

        pub fn loadResource(resource_id: ResourceID.Raw) !void {
            call_count += 1;
            testing.expectEqual(0xBEEF, resource_id);
        }

        pub fn unloadAllResources() void {
            unreachable;
        }
    };

    var machine = MockMachine.new(Stubs);
    try instruction._execute(&machine);
    testing.expectEqual(1, Stubs.call_count);
}
