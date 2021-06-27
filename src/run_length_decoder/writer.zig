/// Create a new writer that will begin writing to the end of the specified destination buffer.
pub fn new(destination: []u8) Instance {
    return Instance{
        .destination = destination,
        .cursor = destination.len,
    };
}

/// The byte-wise writer for the run-length decoder. This writing decompressed bytes
/// to a destination buffer, starting from the end of the buffer and working its way forward.
pub const Instance = struct {
    /// The destination buffer to write to.
    destination: []u8,

    /// The current position of the reader within `destination`.
    /// Starts at the end of the destination buffer and works backward from there.
    /// Note that the cursor is 1 higher than you may expect: e.g. when the cursor is 4,
    /// destination[3] is the next byte to be written.
    cursor: usize,

    /// Consume `count` bytes from the specified source reader (which must implement a `readByte() !u8` method)
    /// and write them to the destination starting at the current cursor.
    /// The copied bytes will be in the reverse order they are returned by the reader:
    /// so { 0xEF, 0xCD, 0xAB } from the source will end up as 0xABCDEF in the destination.
    /// Returns error.DestinationExhausted and does not write any data if there is not enough
    /// space remaining in the destination buffer.
    pub fn writeFromSource(self: *Instance, reader: anytype, count: usize) !void {
        if (self.cursor < count) {
            return error.DestinationExhausted;
        }

        var bytes_remaining = count;
        while (bytes_remaining > 0) : (bytes_remaining -= 1) {
            const byte = try reader.readByte();
            self.uncheckedWriteByte(byte);
        }
    }
    /// Read a sequence of bytes working backwards from an offset in the destination relative
    /// to the current cursor, and write them to the destination starting at the current cursor.
    /// The copied bytes will be in the same order they appeared at the offset:
    /// so { 0xAB, 0xCD, 0xEF } from the offset will end up as 0xABCDEF in the destination.
    /// Returns error.CopyOutOfRange if the offset points outside the already-written bytes
    /// in the destination.
    /// Returns error.DestinationExhausted and does not write any data if there is not enough
    /// space remaining in the destination buffer.
    pub fn copyFromDestination(self: *Instance, count: usize, offset: usize) Error!void {
        if (offset == 0 or offset > (self.destination.len - self.cursor)) {
            return error.CopyOutOfRange;
        }

        if (self.cursor < count) {
            return error.DestinationExhausted;
        }

        // -1 accounts for the fact that our internal cursor is at the "end" of the byte,
        // and is only decremented once we write the byte, to avoid underflowing.
        // The offset we get from Another World's data files assume the cursor indicates
        // the start of the byte.
        var start_index: usize = self.cursor + (offset - 1);
        const end_index = start_index - count;

        while (start_index > end_index) : (start_index -= 1) {
            const byte = self.destination[start_index];
            self.uncheckedWriteByte(byte);
        }
    }

    /// Write a single byte to the cursor at the current offset.
    /// The caller must guarantee that self.cursor > 0.
    fn uncheckedWriteByte(self: *Instance, byte: u8) void {
        self.cursor -= 1;
        self.destination[self.cursor] = byte;
    }

    pub fn isAtEnd(self: Instance) bool {
        return self.cursor == 0;
    }
};

/// The possible errors from a writer instance.
pub const Error = error{
    /// The writer ran out of room in its destination buffer before decoding was completed.
    DestinationExhausted,

    /// The writer attempted to copy bytes from outside the destination buffer.
    CopyOutOfRange,
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const fixedBufferStream = @import("std").io.fixedBufferStream;

const max_usize = @import("std").math.maxInt(usize);

test "writeFromSource writes bytes in reverse order starting at the end of the destination" {
    const source = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    var reader = fixedBufferStream(&source).reader();

    var destination: [4]u8 = undefined;
    var writer = new(&destination);

    try writer.writeFromSource(&reader, 4);
    try testing.expect(writer.isAtEnd());

    const expected = [_]u8{ 0xEF, 0xBE, 0xAD, 0xDE };
    try testing.expectEqualSlices(u8, &expected, &destination);
}

test "writeFromSource returns error.DestinationExhausted if destination does not have space" {
    const source = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    var reader = fixedBufferStream(&source).reader();

    var destination: [2]u8 = undefined;
    var writer = new(&destination);

    try testing.expectError(error.DestinationExhausted, writer.writeFromSource(&reader, 4));
}

test "writeFromSource does not trap on egregiously large count" {
    const source = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    var reader = fixedBufferStream(&source).reader();

    var destination: [2]u8 = undefined;
    var writer = new(&destination);

    try testing.expectError(error.DestinationExhausted, writer.writeFromSource(&reader, max_usize));
}

test "copyFromDestination copies bytes from location in destination relative to current cursor" {
    // Populate the destination with 4 bytes of initial data and set the cursor accordingly.
    var destination = [8]u8{
        0x00, 0x00, 0x00, 0x00,
        0xEF, 0xBE, 0xAD, 0xDE,
    };

    var writer = new(&destination);
    writer.cursor = 4;

    // Copy the last byte (4 bytes ahead of the write cursor)
    try writer.copyFromDestination(1, 4);

    const expected_after_first_copy = [8]u8{
        0x00, 0x00, 0x00, 0xDE,
        0xEF, 0xBE, 0xAD, 0xDE,
    };
    try testing.expectEqualSlices(u8, &expected_after_first_copy, &destination);

    // Copy the last two bytes (the second of which is now 5 bytes ahead of write cursor)
    try writer.copyFromDestination(2, 5);

    const expected_after_second_copy = [8]u8{
        0x00, 0xAD, 0xDE, 0xDE,
        0xEF, 0xBE, 0xAD, 0xDE,
    };
    try testing.expectEqualSlices(u8, &expected_after_second_copy, &destination);

    // Copy the 4th-to-last byte (which is now 4 bytes ahead of write cursor)
    try writer.copyFromDestination(1, 4);
    try testing.expect(writer.isAtEnd());

    const expected_after_third_copy = [8]u8{
        0xEF, 0xAD, 0xDE, 0xDE,
        0xEF, 0xBE, 0xAD, 0xDE,
    };
    try testing.expectEqualSlices(u8, &expected_after_third_copy, &destination);
}

test "copyFromDestination returns error.DestinationExhausted when writing too many bytes" {
    var destination = [5]u8{
        0x00, 0xEF, 0xBE, 0xAD, 0xDE,
    };

    var writer = new(&destination);
    writer.cursor = 1;

    try testing.expectError(error.DestinationExhausted, writer.copyFromDestination(2, 2));
}

test "copyFromDestination does not trap on egregiously large count" {
    var destination = [5]u8{
        0x00, 0xEF, 0xBE, 0xAD, 0xDE,
    };

    var writer = new(&destination);
    writer.cursor = 1;

    try testing.expectError(error.DestinationExhausted, writer.copyFromDestination(max_usize, 2));
}

test "copyFromDestination returns error.CopyOutOfRange when offset is too small" {
    var destination: [8]u8 = undefined;

    var writer = new(&destination);
    try testing.expectError(error.CopyOutOfRange, writer.copyFromDestination(0, 1));
}

test "copyFromDestination returns error.CopyOutOfRange when offset is beyond the end of the buffer" {
    var destination: [8]u8 = undefined;

    var writer = new(&destination);
    try testing.expectError(error.CopyOutOfRange, writer.copyFromDestination(1, 1));
}

test "copyFromDestination does not trap on egregiously large offset" {
    var destination: [8]u8 = undefined;

    var writer = new(&destination);
    try testing.expectError(error.CopyOutOfRange, writer.copyFromDestination(1, max_usize));
}
