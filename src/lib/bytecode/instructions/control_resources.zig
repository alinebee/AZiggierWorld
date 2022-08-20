const anotherworld = @import("../../anotherworld.zig");
const resources = anotherworld.resources;
const vm = anotherworld.vm;

const Opcode = @import("../opcode.zig").Opcode;
const Program = @import("../program.zig").Program;
const Machine = vm.Machine;
const GamePart = vm.GamePart;

/// Loads individual resources or entire game parts into memory.
pub const ControlResources = union(enum) {
    /// Unload all loaded resources and stop audio.
    unload_all,

    /// Load all resources for the specified game part and begin executing its program.
    start_game_part: GamePart,

    /// Load the specified resource individually.
    load_resource: resources.ResourceID,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 3 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const resource_id_or_game_part = try program.read(resources.ResourceID.Raw);

        if (resource_id_or_game_part == 0) {
            return .unload_all;
        } else if (GamePart.parse(resource_id_or_game_part)) |game_part| {
            return Self{ .start_game_part = game_part };
        } else |_| {
            // If the value doesn't match any game part, assume it's a resource ID
            return Self{ .load_resource = resources.ResourceID.cast(resource_id_or_game_part) };
        }
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *Machine) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) !void {
        switch (self) {
            .unload_all => machine.unloadAllResources(),
            .start_game_part => |game_part| machine.scheduleGamePart(game_part),
            .load_resource => |resource_id| try machine.loadResource(resource_id),
        }
    }

    // - Exported constants -

    pub const opcode = Opcode.ControlResources;
    pub const ParseError = Program.ReadError;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = start_game_part;

        const unload_all = [3]u8{ raw_opcode, 0x0, 0x0 };
        const start_game_part = [3]u8{ raw_opcode, 0x3E, 0x85 }; // GamePart.arena_cinematic
        const load_resource = [3]u8{ raw_opcode, 0xDE, 0xAD };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = vm.mockMachine;

test "parse parses unload_all instruction and consumes 3 bytes" {
    const instruction = try expectParse(ControlResources.parse, &ControlResources.Fixtures.unload_all, 3);

    try testing.expectEqual(.unload_all, instruction);
}

test "parse parses start_game_part instruction and consumes 3 bytes" {
    const instruction = try expectParse(ControlResources.parse, &ControlResources.Fixtures.start_game_part, 3);

    try testing.expectEqual(.{ .start_game_part = .arena_cinematic }, instruction);
}

test "parse parses load_resource instruction and consumes 3 bytes" {
    const instruction = try expectParse(ControlResources.parse, &ControlResources.Fixtures.load_resource, 3);

    try testing.expectEqual(.{ .load_resource = resources.ResourceID.cast(0xDEAD) }, instruction);
}

test "execute with unload_all instruction calls unloadAllResources with correct parameters" {
    const instruction: ControlResources = .unload_all;

    var machine = mockMachine(struct {
        pub fn scheduleGamePart(_: GamePart) void {
            unreachable;
        }

        pub fn loadResource(_: resources.ResourceID) !void {
            unreachable;
        }

        pub fn unloadAllResources() void {}
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.unloadAllResources);
}

test "execute with start_game_part instruction calls scheduleGamePart with correct parameters" {
    const instruction = ControlResources{ .start_game_part = .arena_cinematic };

    var machine = mockMachine(struct {
        pub fn scheduleGamePart(game_part: GamePart) void {
            testing.expectEqual(.arena_cinematic, game_part) catch unreachable;
        }

        pub fn loadResource(_: resources.ResourceID) !void {
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
    const instruction = ControlResources{ .load_resource = resources.ResourceID.cast(0xBEEF) };

    var machine = mockMachine(struct {
        pub fn scheduleGamePart(_: GamePart) void {
            unreachable;
        }

        pub fn loadResource(resource_id: resources.ResourceID) !void {
            try testing.expectEqual(resources.ResourceID.cast(0xBEEF), resource_id);
        }

        pub fn unloadAllResources() void {
            unreachable;
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.loadResource);
}
