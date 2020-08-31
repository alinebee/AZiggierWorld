//! Tests that MEMLIST.BIN files from the original Another World are parsed correctly.
//! Requires a `dos_fixture` folder containing Another World DOS game files.

const ResourceDescriptor = @import("../resources/resource_descriptor.zig");

const testing = @import("../utils/testing.zig");
const fixedBufferStream = @import("std").io.fixedBufferStream;

test "ResourceDescriptor.parse parses MEMLIST.BIN correctly" {
    const memlist = @embedFile("fixtures/dos/MEMLIST.BIN");
    const expected_count = 146;

    var reader = fixedBufferStream(memlist).reader();

    var buffer: [expected_count + 10]ResourceDescriptor.Instance = undefined;

    const descriptors = try ResourceDescriptor.parse(reader, &buffer);
    testing.expectEqual(expected_count, descriptors.len);
}