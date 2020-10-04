const ColorID = @import("../../values/color_id.zig");
const Point = @import("../../values/point.zig");

const mem = @import("std").mem;
const introspection = @import("introspection.zig");

/// Returns a video buffer storage that stores a single pixel per byte.
pub fn Instance(comptime width: usize, comptime height: usize) type {
    comptime const Data = [height][width]ColorID.Trusted;

    return struct {
        data: Data = mem.zeroes(Data),

        const Self = @This();

        /// Return the color at the specified point in the buffer.
        /// This is not bounds-checked: specifying an point outside the buffer results in undefined behaviour.
        pub fn uncheckedGet(self: Self, point: Point.Instance) ColorID.Trusted {
            return self.data[@intCast(usize, point.y)][@intCast(usize, point.x)];
        }

        /// Set the color at the specified point in the buffer.
        /// This is not bounds-checked: specifying an point outside the buffer results in undefined behaviour.
        pub fn uncheckedSet(self: *Self, point: Point.Instance, color: ColorID.Trusted) void {
            self.data[@intCast(usize, point.y)][@intCast(usize, point.x)] = color;
        }

        /// Fill the entire buffer with the specified color.
        pub fn fill(self: *Self, color: ColorID.Trusted) void {
            // It would be nice to use mem.set on self.data as a whole,
            // but that doesn't work on multidimensional arrays.
            for (self.data) |*row| {
                mem.set(ColorID.Trusted, row, color);
            }
        }
    };
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "Instance produces storage of the expected size filled with zeroes." {
    const storage = Instance(320, 200){};

    const ExpectedData = [200][320]ColorID.Trusted;

    testing.expectEqual(ExpectedData, @TypeOf(storage.data));

    const expected_data = mem.zeroes(ExpectedData);

    testing.expectEqual(expected_data, storage.data);
}

test "fill replaces all bytes in buffer with specified color" {
    var storage = Instance(4, 4){};

    const before_fill = @TypeOf(storage.data){
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    };

    const after_fill = @TypeOf(storage.data){
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
    };

    testing.expectEqual(before_fill, storage.data);

    storage.fill(15);

    testing.expectEqual(after_fill, storage.data);
}

test "uncheckedGet returns color at point" {
    var storage = Instance(320, 200){};
    storage.data[0][0] = 15;
    storage.data[4][3] = 10;
    storage.data[199][319] = 1;

    testing.expectEqual(15, storage.uncheckedGet(.{ .x = 0, .y = 0 }));
    testing.expectEqual(10, storage.uncheckedGet(.{ .x = 3, .y = 4 }));
    testing.expectEqual(1, storage.uncheckedGet(.{ .x = 319, .y = 199 }));
}

test "uncheckedSet sets color at point" {
    var storage = Instance(320, 200){};

    storage.uncheckedSet(.{ .x = 0, .y = 0 }, 15);
    storage.uncheckedSet(.{ .x = 3, .y = 4 }, 10);
    storage.uncheckedSet(.{ .x = 319, .y = 199 }, 1);

    testing.expectEqual(15, storage.data[0][0]);
    testing.expectEqual(10, storage.data[4][3]);
    testing.expectEqual(1, storage.data[199][319]);
}
