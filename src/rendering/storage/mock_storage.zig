const ColorID = @import("../../values/color_id.zig");
const Point = @import("../../values/point.zig");
const PolygonDrawMode = @import("../../values/polygon_draw_mode.zig");

/// Returns a fake video buffer storage type that defers to the specified struct to implement its functions.
/// Usage:
///   StorageFactory = MockStorage.new(struct {
///     // ... define implementations of `get`, `set` etc. here
///   });
///
///   var buffer = VideoBuffer.new(Storage.new, 320, 200);
pub fn new(comptime Implementation: type) type {
    const Factory = struct {
        pub fn new(comptime w: usize, comptime h: usize) type {
            return struct {
                call_counts: CallCounts = .{},

                pub const width = w;
                pub const height = h;
                const Self = @This();

                pub fn get(self: *Self, point: Point.Instance) ColorID.Trusted {
                    self.call_counts.get += 1;
                    return Implementation.get(point);
                }

                pub fn set(self: *Self, point: Point.Instance, color_id: ColorID.Trusted) void {
                    self.call_counts.set += 1;
                    return Implementation.set(point, color_id);
                }
            };
        }
    };

    return Factory;
}

/// The number of times each method has been called on the mock storage instance.
/// Usage:
///   var buffer = VideoBuffer.new(Storage.new, 320, 200);
///   _ = try buffer.get(point);
///   testing.expectEqual(1, buffer.storage.call_counts.get);
const CallCounts = struct {
    get: usize = 0,
    set: usize = 0,
};
