pub const Instruction = union(enum) {
    /// Read n bytes of compressed data from the current source cursor,
    /// and write them directly to the current destination cursor.
    write_from_source: usize,

    /// Read `count` bytes of uncompressed data from `offset` relative to the current destination cursor,
    /// and write them to the current destination cursor.
    copy_from_destination: struct { count: usize, offset: usize },
};

/// Returns a mock writer that does nothing but track the most recent RLE instruction it was asked to perform.
/// Intended solely for testing RLE instruction parsing: in particular, it will not consume any bytes from
/// a reader when receiving a `writeFromReader` command.
pub fn new() Instance {
    return Instance{ .last_instruction = null };
}

pub const Instance = struct {
    last_instruction: ?Instruction,

    pub fn writeFromSource(self: *Instance, reader: anytype, count: usize) !void {
        self.last_instruction = .{ .write_from_source = count };
    }

    pub fn copyFromDestination(self: *Instance, count: usize, offset: usize) !void {
        self.last_instruction = .{
            .copy_from_destination = .{
                .count = count,
                .offset = offset,
            },
        };
    }
};

// -- Testing --

const testing = @import("../../utils/testing.zig");

const FakeReader = struct {
    fn readByte() void {
        unreachable;
    }
};

test "writeFromReader records correct instruction without consuming any bytes from reader" {
    var writer = new();
    var fakeReader = FakeReader{};

    try writer.writeFromSource(&fakeReader, 16);
    testing.expectEqual(
        .{ .write_from_source = 16 },
        writer.last_instruction,
    );
}

test "copyFromDestination records correct instruction" {
    var writer = new();

    try writer.copyFromDestination(16, 0xDEADBEEF);
    testing.expectEqual(
        .{
            .copy_from_destination = .{
                .count = 16,
                .offset = 0xDEADBEEF,
            },
        },
        writer.last_instruction,
    );
}
