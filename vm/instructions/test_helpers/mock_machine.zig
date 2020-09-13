const Machine = @import("../../machine.zig");
const Video = @import("../../video.zig");
const Point = @import("../../types/point.zig");

/// Returns a fake Machine.Instance that defers to the specified struct to implement its functions.
/// This allows testing of Machine function calls that would produce changes in state that are hard
/// to measure (e.g. drawing on screen or producing audio).
pub fn new(comptime Stubs: type) MockMachine(Stubs) {
    return MockMachine(Stubs){};
}

fn MockMachine(comptime Stubs: type) type {
    return struct {
        const Self = @This();

        registers: [Machine.max_registers]Machine.RegisterValue = [_]Machine.RegisterValue{0} ** Machine.max_registers,

        pub fn drawPolygon(self: *Self, source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: ?Video.PolygonScale) !void {
            Stubs.drawPolygon(source, address, point, scale);
        }
    };
}
