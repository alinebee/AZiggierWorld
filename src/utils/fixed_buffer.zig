const mem = @import("std").mem;

/// A buffer with a fixed size that maintains a dynamic count
/// of how many values in the buffer currently contain valid data.
/// This buffer requires no allocation and is safely copyable and movable.
pub fn Instance(comptime capacity: usize, comptime T: type) type {
    return struct {
        items: [capacity]T,
        len: usize,

        const Self = @This();

        /// A read-only slice of the valid items in the buffer.
        pub fn constSlice(self: Self) []const T {
            return self.items[0..self.len];
        }

        /// A mutable slice of the valid items in the buffer.
        pub fn slice(self: *Self) []T {
            return self.items[0..self.len];
        }

        /// Replace the contents of this buffer with the specified source data.
        /// Traps on checked builds if the source is longer than the capacity of this buffer.
        pub fn copy(self: *Self, source: []const T) void {
            mem.copy(T, self.items[0..source.len], source);
            self.len = source.len;
        }
    };
}

/// Create a new fixed buffer with the specified capacity,
/// filled with the contents of a buffer whose length must be <= the capacity.
/// Traps on checked builds if the source is longer than the capacity.
pub fn new(comptime capacity: usize, comptime T: type, source: []const T) Instance(capacity, T) {
    var self: Instance(capacity, T) = undefined;
    self.copy(source);

    return self;
}

// -- Tests --

const testing = @import("testing.zig");

test "slice reflects current count" {
    var buffer = Instance(10, u8){
        .items = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        .len = 5,
    };

    const expected = [_]u8{ 0, 1, 2, 3, 4 };

    try testing.expectEqualSlices(u8, &expected, buffer.slice());
}

test "const_slice reflects current count" {
    const buffer = Instance(10, u8){
        .items = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        .len = 5,
    };

    const expected = [_]u8{ 0, 1, 2, 3, 4 };

    try testing.expectEqualSlices(u8, &expected, buffer.constSlice());
}

test "copy replaces the contents of the buffer with the source" {
    var buffer: Instance(10, u8) = Instance(10, u8){
        .items = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        .len = 10,
    };

    const source = [_]u8{ 9, 8, 7, 6, 5 };
    buffer.copy(&source);

    try testing.expectEqualSlices(u8, &source, buffer.constSlice());
}

test "new creates a new instance initialized with the specified data" {
    const source = [_]u8{ 9, 8, 7, 6, 5 };

    const buffer = new(10, u8, &source);

    try testing.expectEqualSlices(u8, &source, buffer.constSlice());
}

test "Instance is safe to copy" {
    var buffer = Instance(10, u8){
        .items = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        .len = 5,
    };

    var copy = buffer;

    try testing.expectEqualSlices(u8, buffer.constSlice(), copy.constSlice());
    try testing.expectEqualSlices(u8, buffer.slice(), copy.slice());
    try testing.expect(buffer.slice().ptr != copy.slice().ptr);
    try testing.expect(buffer.constSlice().ptr != copy.constSlice().ptr);
}
