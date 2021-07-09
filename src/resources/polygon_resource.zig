//! Defines functions for parsing Another World's polygon resource data.
//!
//! Another World's polygon resources are stored as a recursive hierarchy:
//! - At the top level are entries which may either be a single polygon or a group of n polygons/subgroups.
//! - Each group of polygons is a variable-length list of "pointers" to other entries within the polygon data.
//!   Those pointers may point to a single polygon or to another group.
//!   Groups also define an x,y offset to apply to all entries within that group;
//!   Each individual pointer can also define its own x,y offset to apply on top of that,
//!   and can also override the draw mode of the polygon it points to.
//!
//! This grouping structure allowed Another World to group multiple polygons into conceptual draw units
//! and to efficiently reuse polygons while applying situation-specific tweaks to them.
//! (It also allows potential recursion cycles, which the parser must manually guard against.)

const Polygon = @import("../rendering/polygon.zig");
const PolygonScale = @import("../values/polygon_scale.zig");
const Point = @import("../values/point.zig");
const DrawMode = @import("../values/draw_mode.zig");

const introspection = @import("../utils/introspection.zig");
const fixedBufferStream = @import("std").io.fixedBufferStream;

/// The offset within a polygon resource from which to read polygon data.
pub const Address = u16;

/// Create a new resource instance that will load data from the specified buffer.
pub fn new(data: []const u8) Instance {
    return .{ .data = data };
}

pub const Instance = struct {
    /// Raw polygon data read from Another World's resource files.
    data: []const u8,

    /// Polygon resources are stored recursively. To prevent infinite recursion
    /// from malformed resources, we return an error once we hit this maximum depth.
    const max_recursion_depth = 10;

    /// Reads polygons from the specified address within the polygon data and calls visitor.visit with each polygon.
    /// Visitor.visit must have the signature: fn (Polygon.Instance) !bool and must return true to continue iteration
    /// or false to stop iterating.
    /// Returns one of Error if malformed data is encountered when reading polygon data or if visitor.visit returns an error.
    pub fn iteratePolygons(self: Instance, address: Address, origin: Point.Instance, scale: PolygonScale.Raw, visitor: anytype) Error(@TypeOf(visitor))!void {
        try self.recursivelyParseEntry(address, origin, scale, null, 0, visitor);
    }

    fn recursivelyParseEntry(self: Instance, address: Address, origin: Point.Instance, scale: PolygonScale.Raw, draw_mode: ?DrawMode.Enum, recursion_depth: usize, visitor: anytype) Error(@TypeOf(visitor))!void {
        if (address >= self.data.len) {
            return error.InvalidAddress;
        }

        if (recursion_depth > max_recursion_depth) {
            return error.PolygonRecursionDepthExceeded;
        }

        var reader = fixedBufferStream(self.data[address..]).reader();

        const header = try EntryHeader.parse(reader);

        switch (header) {
            .single_polygon => |default_draw_mode| {
                const final_draw_mode = draw_mode orelse default_draw_mode;
                const polygon = try Polygon.parse(reader, origin, scale, final_draw_mode);

                const should_continue = try visitor.visit(polygon);

                if (should_continue == false) return;
            },
            .group => {
                const group_header = try GroupHeader.parse(reader, scale);

                const group_origin = Point.Instance{
                    .x = origin.x -% group_header.offset.x,
                    .y = origin.y -% group_header.offset.y,
                };

                var entries_remaining = group_header.count;
                while (entries_remaining > 0) : (entries_remaining -= 1) {
                    const entry = try EntryPointer.parse(reader, scale);

                    const entry_origin = Point.Instance{
                        .x = group_origin.x +% entry.offset.x,
                        .y = group_origin.y +% entry.offset.y,
                    };

                    try self.recursivelyParseEntry(entry.address, entry_origin, scale, entry.draw_mode, recursion_depth + 1, visitor);
                }
            },
        }
    }
};

/// The possible errors that can occur when reading polygon data on behalf of a specified visitor.
pub fn Error(comptime Visitor: type) type {
    const VisitError = introspection.ErrorType(introspection.BaseType(Visitor).visit);
    return VisitError || ParseError;
}

const ReaderType = @import("std").io.FixedBufferStream([]const u8).Reader;

/// The possible errors that can occur when parsing polygon data.
const ParseError = Polygon.Error(ReaderType) || error{
    /// The requested polygon address was out of range, or one of the polygon subentries
    /// within the resource pointed to an address that was out of range.
    InvalidAddress,
    /// A polygon entry had a type code that was not recognized.
    UnknownPolygonEntryType,
    /// The resource contained recursive polygon data that looped back on itself or was nested too deeply.
    PolygonRecursionDepthExceeded,
};

// -- Helper types --

/// Represents the header for polygon data at an address,
/// labelling whether that data is a single polygon or a group of polygons.
const EntryHeader = union(enum) {
    /// The data following the header contains a single polygon,
    /// which should be drawn using the specified draw mode if no override mode has been applied.
    single_polygon: DrawMode.Enum,
    /// The data following the header contains a group of polygons or subgroups.
    group: void,

    /// Parses an entry header from a byte stream containing polygon resource data.
    /// Consumes 1-4 bytes from the reader.
    /// Fails with an error if there are not enough bytes in the stream or the header was an unrecognized type.
    fn parse(reader: anytype) ParseError!EntryHeader {
        // Adapted from the reference implementation:
        // - If the top 2 bits of the control code byte are both set: treat the following bytes
        //   as a single polygon, and the remaining 6 bits of the control code as the draw mode
        //   for that polygon.
        // - Otherwise: if the remaining 6 bits of the control code are equal to 2,
        //   treat the following bytes as a polygon group.
        // - Otherwise: treat the control code as unrecognised and fail.
        //
        // TODO: Figure out if the reference logic is actually correct,
        // by observing the range of control codes used in the actual game data.
        // - Why use the top two bits to denote polygon vs group, instead of a single bit?
        // - Why does the value 2 denote a polygon group? Were more valid control codes planned?

        const code = try reader.readByte();

        const type_flag = code >> 6;
        const data = code & 0b0011_1111;

        if (type_flag == 0b11) {
            const draw_mode = DrawMode.parse(data);
            return EntryHeader{ .single_polygon = draw_mode };
        } else if (data == 0b10) {
            return EntryHeader.group;
        } else {
            return error.UnknownPolygonEntryType;
        }
    }
};

/// Represents the header for a polygon group within polygon resource data.
const GroupHeader = struct {
    /// The x,y distance to offset this group's polygons and subgroups from the parent origin.
    /// Should be subtracted from - not added to - the parent origin.
    offset: Point.Instance,
    /// The number of entries within this group, from 1-256.
    count: usize,

    /// Parses a group header from a byte stream containing polygon resource data.
    /// Consumes 3 bytes from the stream.
    /// Fails with an error if there are not enough bytes in the stream.
    fn parse(reader: anytype, scale: PolygonScale.Raw) ParseError!GroupHeader {
        // Each polygon group is stored as the following bytes:
        // 0: Unscaled X offset at which to draw the group: multiplied by the scale and then *subtracted* from the parent origin.
        // 1: Unscaled Y offset at which to draw the group: multiplied by the scale and then *subtracted* from the parent origin.
        // 2: Number of entries in this group - 1.
        // 3...: the pointers for each entry in this group (see EntryPointer below).
        return GroupHeader{
            .offset = try parseOffset(reader, scale),
            // The entry count is undercounted by 1, so a single group can contain 1-256 entries.
            .count = @intCast(usize, try reader.readByte()) + 1,
        };
    }
};

/// Represents a subentry within a polygon group that acts as a pointer to a polygon or subgroup.
const EntryPointer = struct {
    /// The address of the polygon or subgroup that the entry points to.
    address: Address,
    /// The x,y distance to offset the entry's polygon or subgroup from the parent origin.
    /// Unlike the group offset, this should be added to - not subtracted from - the parent origin.
    offset: Point.Instance,
    /// An optional overridden draw mode for this entry's polygon.
    /// Unused if the entry is a subgroup rather than a single polygon.
    draw_mode: ?DrawMode.Enum,

    /// Parses a single entry pointer from a byte stream containing polygon resource data.
    /// Consumes either 4 or 6 bytes from the stream, depending on the contents of the pointer record.
    /// Fails with an error if there are not enough bytes in the stream.
    fn parse(reader: anytype, scale: PolygonScale.Raw) ParseError!EntryPointer {
        // Each pointer is stored as the following bytes:
        // 0...1: A 16-bit control code with the layout `maaa_aaaa_aaaa_aaaa`, where:
        //        - `m` is a 1-bit flag determining whether to read extra bytes for the override draw mode.
        //        - `a` is the 15-bit right-shifted address (within the same resource) of the polygon or group this entry points to.
        //          (Having pointers to polygons allows the same polygon to be reused within several different groups.)
        // 2:     The unscaled X offset at which to draw the polygon, relative to the overall group.
        //        Multiplied by the scale to get the final offset.
        // 3:     The unscaled Y offset at which to draw the polygon, relative to the overall group.
        //        Multiplied by the scale to get the final offset.
        // 4...5: An extra 16-bit word that will be read only if the top bit of the control code was 1.
        //        This has the layout `xmmm_mmmm_xxxx_xxxx`, where:
        //        - `m` is the draw mode to render the polygon with, overriding the polygon's own draw mode.
        //        - `x` are unused or unknown.
        //          TODO: explore what values these unknown bits hold.
        const code = try reader.readInt(Address, .Big);
        const overrides_draw_mode = (code >> 15) == 0b1;

        var self = EntryPointer{
            .address = code << 1,
            .offset = try parseOffset(reader, scale),
            .draw_mode = undefined,
        };

        if (overrides_draw_mode) {
            // Pointers that override the draw mode are two bytes longer, but only the first byte is used.
            // The second byte is presumably just padding, to ensure that pointers remain an even byte length.
            // Group headers and polygons are also an even length, once you factor in their entry header byte;
            // together this ensures that all polygon addresses stay aligned to 2-byte boundaries, and can be
            // represented in 15 bits instead of 16.
            //
            // Another World takes advantage of this by packing a flag into the top bit of the polygon address,
            // in both the entry pointer and in background draw instructions: see draw_background_polygon.zig
            // for details of the latter.
            const raw_draw_mode = try reader.readByte();
            _ = try reader.readByte();

            // Why did the original implementation mask this? Does the top bit have special meaning?
            self.draw_mode = DrawMode.parse(raw_draw_mode & 0b0111_1111);
        } else {
            self.draw_mode = null;
        }

        return self;
    }
};

// Parse the polygon offset for a group header or entry pointer.
fn parseOffset(reader: anytype, scale: PolygonScale.Raw) ParseError!Point.Instance {
    return Point.Instance{
        .x = PolygonScale.apply(i16, try reader.readByte(), scale),
        .y = PolygonScale.apply(i16, try reader.readByte(), scale),
    };
}

// -- Data examples --

// zig fmt: off
const DataExamples = struct {
    // Individual header examples

    const polygon_entry_header = [_]u8{0b1100_1010}; // Lower 6 bits define draw mode with solid color 0xA (0b1010)
    const group_entry_header = [_]u8{0b0000_0010};
    const invalid_entry_header = [_]u8{0b0000_1111};

    const group_header = [_]u8{
        25,     // X offset
        100,    // Y offset
        2,      // 3 pointers
    };

    const entry_pointer_without_draw_mode = [_]u8{
        0b0000_0000, 12 >> 1,   // Entry address of 12 with custom draw mode flag unset
        25,     // X offset
        100,    // Y offset
    };

    const entry_pointer_with_draw_mode = [_]u8{
        0b1000_0000, 0 >> 1,   // Entry address of 0 with custom draw mode flag set
        50,     // X offset
        200,    // Y offset
        0b1001_0000, // Draw mode 16 = .highlight; top bit should be masked off and ignored
        0b1111_1111, // Unused padding byte
    };

    // - Full resource block

    // Simple 4-vertex polygons @ 12 bytes long each
    const polygon_1 = Polygon.DataExamples.valid_dot;
    const polygon_2 = Polygon.DataExamples.valid_dot;

    const group_1 = [_]u8{
        1, // X negative offset
        1, // Y negative offset
        2, // Contains 3 pointers (undercounted by 1)
    };

    const group_1_pointer_1 = [_]u8{
        0b0000_0000, 12 >> 1,   // Address of polygon 2, no custom draw mode
        11, // X positive offset
        11, // Y positive offset
    };

    const group_1_pointer_2 = [_]u8{
        0b1000_0000, 0 >> 1,    // Address of polygon 1, using custom draw mode
        12, // X positive offset
        12, // Y positive offset
        0b1001_0000, // Draw mode 16 means .highlight; top bit should be masked off and ignored
        0b1111_1111, // Unused padding byte
    };

    const group_1_pointer_3 = [_]u8 {
        0b0000_0000, 42 >> 1,   // Entry address of 42 with custom draw mode flag unset
        13,  // X positive offset
        13,  // Y positive offset
    };

    const group_2 = [_]u8{
        2,  // X offset
        2,  // Y offset
        0,  // Contains 1 pointer (undercounted by 1)
    };

    const group_2_pointer_1 = [_]u8{
        0b1000_0000, 12 >> 1,   // Address of polygon 2, custom draw mode
        21, // X offset
        21, // Y offset
        0b1111_1111, // Draw mode > 16 means .mask; top bit should be masked off and ignored
        0b1111_1111, // Unused padding byte
    };

    // Defines a polygon resource containing 2 raw polygons and 2 groups:
    // - Group 1 points to polygon 2, polygon 1, group 2
    // - Group 2 points to polygon 2
    // Should result in iterating 3 polygons.
    const resource = [_]u8{}
        // Block contents                           // Offset
        // --------------                           // ------
        ++ polygon_entry_header ++ polygon_1        // 0
        ++ polygon_entry_header ++ polygon_2        // 12
        ++ group_entry_header ++ group_1            // 24
        ++ group_1_pointer_1                        // 28 - points to 12
        ++ group_1_pointer_2                        // 32 - points to 0
        ++ group_1_pointer_3                        // 38 - points to 42
        ++ group_entry_header ++ group_2            // 42
        ++ group_2_pointer_1                        // 46 - points to 12
    ;
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const countingReader = @import("std").io.countingReader;

// - EntryHeader tests -

test "EntryHeader.parse parses single polygon entry header correctly and consumes 1 byte" {
    const data = &DataExamples.polygon_entry_header;

    var stream = countingReader(fixedBufferStream(data).reader());

    const actual = try EntryHeader.parse(stream.reader());
    const expected: EntryHeader = .{ .single_polygon = .{ .solid_color = 0xA } };

    try testing.expectEqual(expected, actual);
    try testing.expectEqual(1, stream.bytes_read);
}

test "EntryHeader.parse parses polygon group entry header correctly and consumes 1 byte" {
    const data = &DataExamples.group_entry_header;

    var stream = countingReader(fixedBufferStream(data).reader());

    const actual = try EntryHeader.parse(stream.reader());
    const expected: EntryHeader = .group;

    try testing.expectEqual(expected, actual);
    try testing.expectEqual(1, stream.bytes_read);
}

test "EntryHeader.parse fails with error.UnknownPolygonEntryType and consumes 1 byte when header is invalid" {
    const data = &DataExamples.invalid_entry_header;

    var stream = countingReader(fixedBufferStream(data).reader());

    try testing.expectError(error.UnknownPolygonEntryType, EntryHeader.parse(stream.reader()));
    try testing.expectEqual(1, stream.bytes_read);
}

test "EntryHeader.parse fails with error.EndOfStream and consumes 0 bytes on truncated header" {
    const data = [_]u8{};

    var stream = countingReader(fixedBufferStream(&data).reader());

    try testing.expectError(error.EndOfStream, EntryHeader.parse(stream.reader()));
    try testing.expectEqual(0, stream.bytes_read);
}

// - GroupHeader tests -

test "GroupHeader.parse correctly parses group header with scaled offset and consumes 3 bytes" {
    const data = &DataExamples.group_header;

    var stream = countingReader(fixedBufferStream(data).reader());

    const actual = try GroupHeader.parse(stream.reader(), PolygonScale.default * 2);
    const expected = GroupHeader{
        .offset = .{
            .x = 50,
            .y = 200,
        },
        .count = 3,
    };

    try testing.expectEqual(expected, actual);
    try testing.expectEqual(3, stream.bytes_read);
}

test "GroupHeader.parse fails with error.EndOfStream and consumes all remaining bytes on truncated header" {
    const data = DataExamples.group_header[0..2];

    var stream = countingReader(fixedBufferStream(data).reader());

    try testing.expectError(error.EndOfStream, GroupHeader.parse(stream.reader(), PolygonScale.default * 2));
    try testing.expectEqual(2, stream.bytes_read);
}

// - EntryPointer tests -

test "EntryPointer.parse correctly parses pointer without custom draw mode and consumes 4 bytes" {
    const data = &DataExamples.entry_pointer_without_draw_mode;

    var stream = countingReader(fixedBufferStream(data).reader());

    const actual = try EntryPointer.parse(stream.reader(), PolygonScale.default * 2);
    const expected = EntryPointer{
        .address = 12,
        .offset = .{
            .x = 50,
            .y = 200,
        },
        .draw_mode = null,
    };

    try testing.expectEqual(expected, actual);
    try testing.expectEqual(4, stream.bytes_read);
}

test "EntryPointer.parse correctly parses pointer with custom draw mode and consumes 6 bytes" {
    const data = &DataExamples.entry_pointer_with_draw_mode;

    var stream = countingReader(fixedBufferStream(data).reader());

    const actual = try EntryPointer.parse(stream.reader(), PolygonScale.default * 2);
    const expected = EntryPointer{
        .address = 0,
        .offset = .{
            .x = 100,
            .y = 400,
        },
        .draw_mode = .highlight,
    };

    try testing.expectEqual(expected, actual);
    try testing.expectEqual(6, stream.bytes_read);
}

test "EntryPointer.parse fails with error.EndOfStream and consumes all remaining bytes on truncated header without custom draw mode" {
    const data = DataExamples.entry_pointer_without_draw_mode[0..3];

    var stream = countingReader(fixedBufferStream(data).reader());

    try testing.expectError(error.EndOfStream, EntryPointer.parse(stream.reader(), PolygonScale.default * 2));
    try testing.expectEqual(3, stream.bytes_read);
}

test "EntryPointer.parse fails with error.EndOfStream and consumes all remaining bytes on truncated header with custom draw mode" {
    const data = DataExamples.entry_pointer_with_draw_mode[0..4];

    var stream = countingReader(fixedBufferStream(data).reader());

    try testing.expectError(error.EndOfStream, EntryPointer.parse(stream.reader(), PolygonScale.default * 2));
    try testing.expectEqual(4, stream.bytes_read);
}

// - iteratePolygons tests -

const ArrayList = @import("std").ArrayList;
const Allocator = @import("std").mem.Allocator;

const TestVisitor = struct {
    polygons: ArrayList(Polygon.Instance),

    fn init(allocator: *Allocator) TestVisitor {
        return .{
            .polygons = ArrayList(Polygon.Instance).init(allocator),
        };
    }

    fn deinit(self: TestVisitor) void {
        self.polygons.deinit();
    }

    fn visit(self: *TestVisitor, polygon: Polygon.Instance) !bool {
        try self.polygons.append(polygon);
        return true;
    }
};

test "iteratePolygons correctly visits all polygons in group" {
    const resource = new(&DataExamples.resource);

    var visitor = TestVisitor.init(testing.allocator);
    defer visitor.deinit();

    const origin = .{ .x = 1000, .y = 2000 };
    const address = 24; // First group in resource data

    try resource.iteratePolygons(address, origin, PolygonScale.default, &visitor);

    try testing.expectEqual(3, visitor.polygons.items.len);

    const polygon_1 = visitor.polygons.items[0];
    // [origin] - [group 1 offset] + [group 1 pointer 1 offset]
    try testing.expectEqual(1000 - 1 + 11, polygon_1.bounds.x.min);
    try testing.expectEqual(2000 - 1 + 11, polygon_1.bounds.y.min);
    try testing.expectEqual(.{ .solid_color = 0xA }, polygon_1.draw_mode);
    try testing.expectEqual(4, polygon_1.count);

    const polygon_2 = visitor.polygons.items[1];
    // [origin] - [group 1 offset] + [group 1 pointer 2 offset]
    try testing.expectEqual(1000 - 1 + 12, polygon_2.bounds.x.min);
    try testing.expectEqual(2000 - 1 + 12, polygon_2.bounds.y.min);
    try testing.expectEqual(.highlight, polygon_2.draw_mode);
    try testing.expectEqual(4, polygon_2.count);

    const polygon_3 = visitor.polygons.items[2];
    // [origin] - [group 1 offset] + [group 1 pointer 3 offset] - [group 2 offset] + [group 2 pointer 1 offset]
    try testing.expectEqual(1000 - 1 + 13 - 2 + 21, polygon_3.bounds.x.min);
    try testing.expectEqual(2000 - 1 + 13 - 2 + 21, polygon_3.bounds.y.min);
    try testing.expectEqual(.mask, polygon_3.draw_mode);
    try testing.expectEqual(4, polygon_3.count);
}

test "iteratePolygons fails with error.PolygonRecursionDepthExceeded on circular reference in polygon data" {}

test "iteratePolygons fails with error.InvalidAddress if requested address does not exist" {}

test "iteratePolygons fails with error.InvalidAddress if entry pointer within data points to address that does not exist" {}

test "iteratePolygons fails with error.EndOfStream on truncated polygon data" {}
