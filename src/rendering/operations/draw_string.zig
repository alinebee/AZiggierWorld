const ColorID = @import("../../values/color_id.zig");
const BoundingBox = @import("../../values/bounding_box.zig");
const Point = @import("../../values/point.zig");
const Font = @import("../../assets/font.zig");

/// Draw a single or multiline string in the specified color,
/// positioning the top left corner of the text at the specified origin point.
/// Returns an error if the string contains unsupported characters
/// or tried to draw a character outside of the buffer's bounds.
pub fn drawString(comptime Buffer: type, buffer: anytype, string: []const u8, color: ColorID.Trusted, origin: Point.Instance) !void {
    const operation = Buffer.DrawOperation.solidColor(color);

    var cursor = origin;
    for (string) |char| {
        switch (char) {
            '\n' => {
                cursor.x = origin.x;
                cursor.y += Font.glyph_height;
            },
            else => {
                const glyph = try Font.glyph(char);
                try drawGlyph(Buffer, buffer, glyph, cursor, operation);
                cursor.x += Font.glyph_width;
            },
        }
    }
}

/// Draws the specified 8x8 glyph in a solid color, positioning its top left corner at the specified point.
/// Returns error.GlyphOutOfBounds if the glyph's bounds do not lie fully inside the buffer.
fn drawGlyph(comptime Buffer: type, buffer: *Buffer, glyph: Font.Glyph, origin: Point.Instance, operation: Buffer.DrawOperation) Error!void {
    const glyph_bounds = BoundingBox.new(origin.x, origin.y, origin.x + Font.glyph_width, origin.y + Font.glyph_height);

    if (Buffer.bounds.encloses(glyph_bounds) == false) {
        return error.GlyphOutOfBounds;
    }

    var cursor = origin;

    // Walk through each row of the glyph drawing spans of lit pixels.
    for (glyph) |row| {
        var remaining_pixels = row;
        var span_start: Point.Coordinate = cursor.x;
        var span_width: Point.Coordinate = 0;

        // Stop drawing the line as soon as there are no more lit pixels in it.
        while (remaining_pixels != 0) {
            const pixel_lit = (remaining_pixels & 0b1000_0000) != 0;
            remaining_pixels <<= 1;

            // Accumulate lit pixels into a single span for more efficient drawing.
            if (pixel_lit == true) span_width += 1;

            // If we reach an unlit pixel, or the last lit pixel of the row,
            // draw the current span of lit pixels and start a new span.
            if (pixel_lit == false or remaining_pixels == 0) {
                if (span_width > 0) {
                    const span_end = span_start + span_width - 1;
                    buffer.uncheckedDrawSpan(.{ .min = span_start, .max = span_end }, cursor.y, operation);

                    span_start += span_width;
                    span_width = 0;
                }
                span_start += 1;
            }
        }

        // Once we've consumed all pixels in the row, move down to the next one.
        cursor.y += 1;
    }
}

/// The possible errors from a string drawing operation.
pub const Error = Font.Error || error{
    /// Attempted to draw a glyph partially or entirely outside the buffer.
    GlyphOutOfBounds,
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const expectPixels = @import("../test_helpers/storage_test_suite.zig").expectPixels;

/// Given a function that takes a width and a height and returns a type that implements the storage interface,
/// test drawString against that storage type.
fn runTests(comptime BufferFn: anytype) void {
    _ = struct {
        test "drawString renders pixels of glyph at specified position in buffer" {
            const Buffer = BufferFn(42, 18);

            var buffer = Buffer{};
            buffer.fill(0x0);

            const string = "Hello\nWorld";
            try drawString(Buffer, &buffer, string, 0x1, .{ .x = 1, .y = 1 });

            const expected =
                \\000000000000000000000000000000000000000000
                \\010000100000000000001000000010000000000000
                \\010000100000000000001000000010000000000000
                \\010000100001110000001000000010000001110000
                \\011111100010001000001000000010000010001000
                \\010000100011111000001000000010000010001000
                \\010000100010000000001000000010000010001000
                \\010000100001111000001000000010000001110000
                \\000000000000000000000000000000000000000000
                \\010000010000000000000000000010000000001000
                \\010000010000000000000000000010000000001000
                \\010000010001110000100110000010000001111000
                \\010000010010001000111000000010000010001000
                \\010010010010001000100000000010000010001000
                \\010101010010001000100000000010000010001000
                \\011000110001110000100000000010000001111000
                \\000000000000000000000000000000000000000000
                \\000000000000000000000000000000000000000000
            ;

            try expectPixels(expected, buffer);
        }

        test "drawString returns error.OutOfBounds for glyphs that are not fully inside the buffer" {
            const Buffer = BufferFn(10, 10);

            var buffer = Buffer{};

            try testing.expectError(error.GlyphOutOfBounds, drawString(Buffer, &buffer, "_", 0xB, .{ .x = -1, .y = -2 }));
            try testing.expectError(error.GlyphOutOfBounds, drawString(Buffer, &buffer, "_", 0xB, .{ .x = 312, .y = 192 }));
        }

        test "drawString returns error.InvalidCharacter for characters that don't have glyphs defined" {
            const Buffer = BufferFn(10, 10);

            var buffer = Buffer{};

            try testing.expectError(error.InvalidCharacter, drawString(Buffer, &buffer, "\u{0}", 0xB, .{ .x = 1, .y = 1 }));
        }
    };
}

const AlignedStorage = @import("../storage/aligned_storage.zig");
const PackedStorage = @import("../storage/packed_storage.zig");

test "Run tests with aligned storage" {
    runTests(AlignedStorage.Instance);
}

test "Run tests with packed storage" {
    runTests(PackedStorage.Instance);
}
