const ColorID = @import("../../values/color_id.zig").ColorID;

const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const debug = std.debug;

/// Stores a 16-color bitmap with the specified width and height, and converts its contents
/// to and from a multiline string representation. Intended for unit-testing the contents of a draw buffer.
pub fn IndexedBitmap(comptime width: usize, comptime height: usize) type {
    // Store pixel data in a two-dimensional array
    const Row = [width]ColorID;
    const Data = [height]Row;

    // We sometimes also address pixels as a 1D array, e.g. for fills
    const bytes_required = width * height;
    const RawData = [bytes_required]ColorID;
    comptime debug.assert(@sizeOf(Data) == @sizeOf(RawData));

    return struct {
        data: Data = undefined,

        const Self = @This();

        /// Return a fixed bitmap filled with the specified color.
        pub fn filled(color_id: ColorID) Self {
            var self = Self{};
            const raw_bytes = @ptrCast(*RawData, &self.data);
            mem.set(ColorID, raw_bytes, color_id);
            return self;
        }

        /// Creates a new bitmap from a multiline string, where rows of the bitmap are lines
        /// of uppercase hexadecimal color values from '0' to 'F', followed by a newline.
        /// Any non-hexadecimal characters are treated as a fatal error.
        ///
        /// Example:
        /// const bitmap4x4 = Instance(4, 4).fromString(
        ///     \\0000
        ///     \\FFFF
        ///     \\1234
        ///     \\ABCD
        /// );
        pub fn fromString(string: []const u8) Self {
            var self: Self = .{ .data = undefined };

            for (self.data) |*row, y| {
                for (row) |*color, x| {
                    // Each line of pixels is expected to be terminated by a newline character
                    // which is skipped when parsing the string.
                    const line_width = width + 1;
                    const index = (y * line_width) + x;

                    color.* = switch (string[index]) {
                        '0' => ColorID.cast(0),
                        '1' => ColorID.cast(1),
                        '2' => ColorID.cast(2),
                        '3' => ColorID.cast(3),
                        '4' => ColorID.cast(4),
                        '5' => ColorID.cast(5),
                        '6' => ColorID.cast(6),
                        '7' => ColorID.cast(7),
                        '8' => ColorID.cast(8),
                        '9' => ColorID.cast(9),
                        'A' => ColorID.cast(10),
                        'B' => ColorID.cast(11),
                        'C' => ColorID.cast(12),
                        'D' => ColorID.cast(13),
                        'E' => ColorID.cast(14),
                        'F' => ColorID.cast(15),
                        else => |unknown_char| {
                            std.debug.panic("Only uppercase hexadecimal characters (0-F) are supported, got '{c}' at index #{}", .{ unknown_char, index });
                        },
                    };
                }
            }
            return self;
        }

        /// Dumps the contents of the bitmap as a multiline string of uppercase hexadecimal color values,
        /// with newlines between each row of pixels.
        pub fn format(self: Self, comptime _: []const u8, options: fmt.FormatOptions, writer: anytype) !void {
            for (self.data) |row, index| {
                for (row) |color| {
                    try fmt.formatIntValue(color.index(), "X", options, writer);
                }
                if (index != height - 1) {
                    try writer.writeByte('\n');
                }
            }
        }
    };
}

/// Assert that a bitmap's contents match an expected ASCII hex string representation.
/// Prints the difference between them as a hex string in case of a mismatch.
///
/// Usage:
/// ------
/// const expected =
///     \\0123
///     \\4567
///     \\89AB
///     \\CDEF
/// ;
/// const actual = my_buffer.toBitmap();
/// expectBitmap(expected, actual);
pub fn expectBitmap(expected: []const u8, actual: anytype) !void {
    const actual_formatted = try fmt.allocPrint(testing.allocator, "{}", .{actual});
    defer testing.allocator.free(actual_formatted);

    try testing.expectEqualStrings(expected, actual_formatted);
}

/// Assert that a bitmap's contents match those of another bitmap.
/// Prints the difference between them as a hex string in case of a mismatch.
///
/// Usage:
/// ------
/// const expected = IndexedBitmap.filled(0);
/// const actual = my_buffer.toBitmap();
/// expectEqualBitmaps(expected, actual);
pub fn expectEqualBitmaps(expected: anytype, actual: @TypeOf(expected)) !void {
    const expected_formatted = try fmt.allocPrint(testing.allocator, "{}", .{expected});
    defer testing.allocator.free(expected_formatted);

    const actual_formatted = try fmt.allocPrint(testing.allocator, "{}", .{actual});
    defer testing.allocator.free(actual_formatted);

    try testing.expectEqualStrings(expected_formatted, actual_formatted);
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "fromString populates bitmap data correctly from multiline string" {
    const bitmap = IndexedBitmap(4, 4).fromString(
        \\0123
        \\4567
        \\89AB
        \\CDEF
    );

    const expected = @bitCast(@TypeOf(bitmap.data), [4][4]ColorID.Trusted{
        .{ 00, 01, 02, 03 },
        .{ 04, 05, 06, 07 },
        .{ 08, 09, 10, 11 },
        .{ 12, 13, 14, 15 },
    });

    try testing.expectEqual(expected, bitmap.data);
}

test "fileld populates bitmap data correctly" {
    const bitmap = IndexedBitmap(4, 4).filled(ColorID.cast(15));

    const expected = @bitCast(@TypeOf(bitmap.data), [4][4]ColorID.Trusted{
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
        .{ 15, 15, 15, 15 },
    });

    try testing.expectEqual(expected, bitmap.data);
}

test "format prints colors as lines of hex values" {
    const bitmap = IndexedBitmap(4, 4){
        .data = @bitCast([4][4]ColorID, [4][4]ColorID.Trusted{
            .{ 00, 01, 02, 03 },
            .{ 04, 05, 06, 07 },
            .{ 08, 09, 10, 11 },
            .{ 12, 13, 14, 15 },
        }),
    };

    const expected_output =
        \\0123
        \\4567
        \\89AB
        \\CDEF
    ;

    const actual_output = try fmt.allocPrint(testing.allocator, "{}", .{bitmap});
    defer testing.allocator.free(actual_output);

    try testing.expectEqualStrings(expected_output, actual_output);
}

test "expectBitmap compares bitmap correctly against string" {
    const bitmap = IndexedBitmap(4, 4){
        .data = @bitCast([4][4]ColorID, [4][4]ColorID.Trusted{
            .{ 00, 01, 02, 03 },
            .{ 04, 05, 06, 07 },
            .{ 08, 09, 10, 11 },
            .{ 12, 13, 14, 15 },
        }),
    };

    const expected =
        \\0123
        \\4567
        \\89AB
        \\CDEF
    ;
    try expectBitmap(expected, bitmap);
}

test "expectedEqualBitmaps compares two bitmaps correctly" {
    const expected = IndexedBitmap(4, 4){
        .data = @bitCast([4][4]ColorID, [4][4]ColorID.Trusted{
            .{ 00, 01, 02, 03 },
            .{ 04, 05, 06, 07 },
            .{ 08, 09, 10, 11 },
            .{ 12, 13, 14, 15 },
        }),
    };

    const actual = IndexedBitmap(4, 4){
        .data = @bitCast([4][4]ColorID, [4][4]ColorID.Trusted{
            .{ 00, 01, 02, 03 },
            .{ 04, 05, 06, 07 },
            .{ 08, 09, 10, 11 },
            .{ 12, 13, 14, 15 },
        }),
    };

    try expectEqualBitmaps(expected, actual);
}

test "Malformed strings cause panic" {
    // Uncomment to panic
    // const invalid_format =
    //     \\012
    //     \\4567
    //     \\89AB
    //     \\CDEF
    // ;
    //_ = Instance(4, 4).fromString(invalid_format);
}
