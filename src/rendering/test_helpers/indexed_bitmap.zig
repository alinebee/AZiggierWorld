const ColorID = @import("../../values/color_id.zig");

const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;

/// Stores a 16-color bitmap with the specified width and height, and converts its contents
/// to and from a multiline string representation. Intended for unit-testing the contents of a draw buffer.
pub fn Instance(comptime width: usize, comptime height: usize) type {
    comptime const Data = [height][width]ColorID.Trusted;
    return struct {
        data: Data = mem.zeroes(Data),

        const Self = @This();

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
                        '0' => 0,
                        '1' => 1,
                        '2' => 2,
                        '3' => 3,
                        '4' => 4,
                        '5' => 5,
                        '6' => 6,
                        '7' => 7,
                        '8' => 8,
                        '9' => 9,
                        'A' => 10,
                        'B' => 11,
                        'C' => 12,
                        'D' => 13,
                        'E' => 14,
                        'F' => 15,
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
        pub fn format(self: Self, comptime _format: []const u8, options: fmt.FormatOptions, writer: anytype) !void {
            for (self.data) |row, index| {
                for (row) |color| {
                    try fmt.formatIntValue(color, "X", options, writer);
                }
                if (index != height - 1) {
                    try writer.writeByte('\n');
                }
            }
        }
    };
}

/// Assert that a bitmap's contents match an expected ASCII string representation. Example:
/// const expected =
///     \\0123
///     \\4567
///     \\89AB
///     \\CDEF
/// ;
/// expectBitmap(expected, bitmap);
pub fn expectBitmap(expected: []const u8, actual: anytype) !void {
    const actual_formatted = fmt.allocPrint(testing.allocator, "{}", .{actual}) catch unreachable;
    defer testing.allocator.free(actual_formatted);

    try testing.expectEqualStrings(expected, actual_formatted);
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "fromString populates bitmap data correctly from multiline string" {
    const bitmap = Instance(4, 4).fromString(
        \\0123
        \\4567
        \\89AB
        \\CDEF
    );

    const expected: @TypeOf(bitmap.data) = .{
        .{ 00, 01, 02, 03 },
        .{ 04, 05, 06, 07 },
        .{ 08, 09, 10, 11 },
        .{ 12, 13, 14, 15 },
    };

    try testing.expectEqual(expected, bitmap.data);
}

test "format prints colors as lines of hex values" {
    const bitmap = Instance(4, 4){
        .data = .{
            .{ 00, 01, 02, 03 },
            .{ 04, 05, 06, 07 },
            .{ 08, 09, 10, 11 },
            .{ 12, 13, 14, 15 },
        },
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

test "expectBitmap compares bitmaps correctly" {
    const bitmap = Instance(4, 4){
        .data = .{
            .{ 00, 01, 02, 03 },
            .{ 04, 05, 06, 07 },
            .{ 08, 09, 10, 11 },
            .{ 12, 13, 14, 15 },
        },
    };

    const expected =
        \\0123
        \\4567
        \\89AB
        \\CDEF
    ;
    try expectBitmap(expected, bitmap);
}

test "Malformed strings cause panic" {
    const invalid_format =
        \\012
        \\4567
        \\89AB
        \\CDEF
    ;

    // Uncomment to panic
    //_ = Instance(4, 4).fromString(invalid_format);
}
