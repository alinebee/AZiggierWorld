const Machine = @import("../../machine.zig");
const Video = @import("../../video.zig");
const Point = @import("../../types/point.zig");

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
            Implementation.drawPolygon(source, address, point, scale);
        }
    };
}

// -- Tests --

const testing = @import("../../../utils/testing.zig");

test "MockMachine calls drawPolygon correctly on stub implementation" {
    const Stubs = struct {
        var call_count: usize = 0;

        fn drawPolygon(source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: ?Video.PolygonScale) void {
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
