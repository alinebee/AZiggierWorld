const Machine = @import("../../machine.zig");
const Video = @import("../../video.zig");

const Point = @import("../../types/point.zig");
const GamePart = @import("../../types/game_part.zig");
const ResourceID = @import("../../types/resource_id.zig");

const zeroes = @import("std").mem.zeroes;

/// Returns a fake Machine.Instance that defers to the specified struct to implement its functions.
/// This allows testing of Machine function calls that would produce changes in state that are hard
/// to measure (e.g. drawing on screen or producing audio).
pub fn new(comptime Implementation: type) MockMachine(Implementation) {
    return MockMachine(Implementation){
        .registers = zeroes(Machine.Registers),
    };
}

fn MockMachine(comptime Implementation: type) type {
    return struct {
        registers: Machine.Registers,

        const Self = @This();

        pub fn drawPolygon(self: *Self, source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: ?Video.PolygonScale) !void {
            try Implementation.drawPolygon(source, address, point, scale);
        }

        pub fn startGamePart(self: *Self, game_part: GamePart.Enum) !void {
            try Implementation.startGamePart(game_part);
        }

        pub fn loadResource(self: *Self, resource_id: ResourceID.Raw) !void {
            try Implementation.loadResource(resource_id);
        }

        pub fn unloadAllResources(self: *Self) void {
            Implementation.unloadAllResources();
        }
    };
}

// -- Tests --

const testing = @import("../../../utils/testing.zig");

test "MockMachine calls drawPolygon correctly on stub implementation" {
    const Stubs = struct {
        var call_count: usize = 0;

        fn drawPolygon(source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: ?Video.PolygonScale) !void {
            call_count += 1;
            testing.expectEqual(.animations, source);
            testing.expectEqual(0xBEEF, address);
            testing.expectEqual(320, point.x);
            testing.expectEqual(200, point.y);
            testing.expectEqual(128, scale);
        }
    };

    var mock = new(Stubs);
    try mock.drawPolygon(.animations, 0xBEEF, .{ .x = 320, .y = 200 }, 128);
    testing.expectEqual(1, Stubs.call_count);
}

test "MockMachine calls startGamePart correctly on stub implementation" {
    const Stubs = struct {
        var call_count: usize = 0;

        fn startGamePart(game_part: GamePart.Enum) !void {
            call_count += 1;
            testing.expectEqual(.copy_protection, game_part);
        }
    };

    var mock = new(Stubs);
    try mock.startGamePart(.copy_protection);
    testing.expectEqual(1, Stubs.call_count);
}

test "MockMachine calls loadResource correctly on stub implementation" {
    const Stubs = struct {
        var call_count: usize = 0;

        fn loadResource(resource_id: ResourceID.Raw) !void {
            call_count += 1;
            testing.expectEqual(0x8BAD, resource_id);
        }
    };

    var mock = new(Stubs);
    try mock.loadResource(0x8BAD);
    testing.expectEqual(1, Stubs.call_count);
}

test "MockMachine calls unloadAllResources correctly on stub implementation" {
    const Stubs = struct {
        var call_count: usize = 0;

        fn unloadAllResources() void {
            call_count += 1;
        }
    };

    var mock = new(Stubs);
    mock.unloadAllResources();
    testing.expectEqual(1, Stubs.call_count);
}
