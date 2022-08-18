const anotherworld = @import("../../anotherworld.zig");

const Surface = @import("../surface.zig").Surface;
const ColorID = @import("../color_id.zig").ColorID;
const PaletteFixtures = @import("../palette.zig").Fixtures;

const testing = @import("utils").testing;
const expectBitmap = @import("indexed_bitmap.zig").expectBitmap;
const planar_bitmap = @import("../planar_bitmap.zig");

// -- Test helpers --

/// Compare the contents of a video buffer against an expected string.
pub fn expectPixels(expected: []const u8, actual: anytype) !void {
    const bitmap = actual.toBitmap();
    try expectBitmap(expected, bitmap);
}

// -- Tests --

/// Given a function that takes a width and height and constructs a video buffer type,
/// runs a suite of tests against the public interface of that type.
///
/// Usage:
/// ------
///   const buffer_test_suite = @import("buffer_test_suite.zig");
///
///   test "Run buffer interface tests" {
///      buffer_test_suite.runTests(FnThatReturnsBufferType);
///   }
pub fn runTests(comptime Instance: anytype) void {
    // Wrap the set of tests in a generic struct, where each test uses the specified buffer constructor function.
    _ = struct {
        test "fill replaces all bytes in buffer with specified color" {
            var buffer = Instance(4, 4){};
            buffer.fill(ColorID.cast(0xA));

            const expected =
                \\AAAA
                \\AAAA
                \\AAAA
                \\AAAA
            ;

            try expectPixels(expected, buffer);
        }

        test "uncheckedDrawSpan with byte-aligned span sets solid color in slice" {
            const Buffer = Instance(10, 3);
            var buffer = Buffer{};
            buffer.fill(ColorID.cast(0x0));

            const operation = Buffer.DrawOperation.solidColor(ColorID.cast(0xD));

            buffer.uncheckedDrawSpan(.{ .min = 2, .max = 7 }, 1, operation);

            const expected =
                \\0000000000
                \\00DDDDDD00
                \\0000000000
            ;
            try expectPixels(expected, buffer);
        }

        test "uncheckedDrawSpan with non-byte-aligned start sets start pixel correctly" {
            const Buffer = Instance(10, 3);
            var buffer = Buffer{};
            buffer.fill(ColorID.cast(0x0));

            const operation = Buffer.DrawOperation.solidColor(ColorID.cast(0xC));

            buffer.uncheckedDrawSpan(.{ .min = 1, .max = 7 }, 1, operation);

            const expected =
                \\0000000000
                \\0CCCCCCC00
                \\0000000000
            ;
            try expectPixels(expected, buffer);
        }

        test "uncheckedDrawSpan with non-byte-aligned end sets end pixel correctly" {
            const Buffer = Instance(10, 3);
            var buffer = Buffer{};
            buffer.fill(ColorID.cast(0x0));

            const operation = Buffer.DrawOperation.solidColor(ColorID.cast(0x3));

            buffer.uncheckedDrawSpan(.{ .min = 2, .max = 8 }, 1, operation);

            const expected =
                \\0000000000
                \\0033333330
                \\0000000000
            ;
            try expectPixels(expected, buffer);
        }

        test "uncheckedDrawSpan with non-byte-aligned start and end sets start and end pixels correctly" {
            const Buffer = Instance(10, 3);
            var buffer = Buffer{};
            buffer.fill(ColorID.cast(0x0));

            const operation = Buffer.DrawOperation.solidColor(ColorID.cast(0x7));

            buffer.uncheckedDrawSpan(.{ .min = 1, .max = 8 }, 1, operation);

            const expected =
                \\0000000000
                \\0777777770
                \\0000000000
            ;
            try expectPixels(expected, buffer);
        }

        test "uncheckedDrawSpan highlights colors in slice" {
            const Buffer = Instance(16, 3);
            var buffer = Buffer{};
            buffer.fillFromString(
                \\0123456789ABCDEF
                \\0123456789ABCDEF
                \\0123456789ABCDEF
            );

            const operation = Buffer.DrawOperation.highlight();

            buffer.uncheckedDrawSpan(.{ .min = 0, .max = 15 }, 1, operation);

            // Colors from 0-7 should have been ramped up to 8-F;
            // Colors from 8-F should have been left as they were.
            const expected =
                \\0123456789ABCDEF
                \\89ABCDEF89ABCDEF
                \\0123456789ABCDEF
            ;
            try expectPixels(expected, buffer);
        }

        test "uncheckedDrawSpan replaces colors in slice with mask" {
            const Buffer = Instance(10, 3);
            var buffer = Buffer{};
            buffer.fill(ColorID.cast(0x0));

            var mask_buffer = Buffer{};
            mask_buffer.fillFromString(
                \\0123456789
                \\9876543210
                \\0123456789
            );

            const operation = Buffer.DrawOperation.mask(&mask_buffer);

            buffer.uncheckedDrawSpan(.{ .min = 3, .max = 6 }, 1, operation);

            const expected =
                \\0000000000
                \\0006543000
                \\0000000000
            ;
            try expectPixels(expected, buffer);
        }

        test "copy replaces contents of destination buffer when offset is 0" {
            const Buffer = Instance(4, 4);
            var source = Buffer{};
            var destination = Buffer{};

            source.fillFromString(
                \\0123
                \\4567
                \\89AB
                \\CDEF
            );

            destination.fill(ColorID.cast(0x7));
            destination.copy(&source, 0);

            const expected =
                \\0123
                \\4567
                \\89AB
                \\CDEF
            ;

            try expectPixels(expected, destination);
        }

        test "copy copies contents of destination buffer into correct positive offset" {
            const Buffer = Instance(4, 4);
            var source = Buffer{};
            var destination = Buffer{};

            source.fillFromString(
                \\0123
                \\4567
                \\89AB
                \\CDEF
            );

            destination.fill(ColorID.cast(0x7));

            destination.copy(&source, 3);

            const expected =
                \\7777
                \\7777
                \\7777
                \\0123
            ;

            try expectPixels(expected, destination);
        }

        test "copy copies contents of destination buffer into correct negative offset" {
            const Buffer = Instance(4, 4);
            var source = Buffer{};
            var destination = Buffer{};

            source.fillFromString(
                \\0123
                \\4567
                \\89AB
                \\CDEF
            );

            destination.fill(ColorID.cast(0x7));

            destination.copy(&source, -3);

            const expected =
                \\CDEF
                \\7777
                \\7777
                \\7777
            ;

            try expectPixels(expected, destination);
        }

        test "copy copies does nothing when offset is too far above the top of the buffer" {
            const Buffer = Instance(4, 4);
            var source = Buffer{};
            var destination = Buffer{};

            source.fillFromString(
                \\0123
                \\4567
                \\89AB
                \\CDEF
            );

            destination.fill(ColorID.cast(0x7));

            destination.copy(&source, -4);
            const expected =
                \\7777
                \\7777
                \\7777
                \\7777
            ;

            try expectPixels(expected, destination);
        }

        test "copy copies does nothing when offset is too far below the bottom of the buffer" {
            const Buffer = Instance(4, 4);
            var source = Buffer{};
            var destination = Buffer{};

            source.fillFromString(
                \\0123
                \\4567
                \\89AB
                \\CDEF
            );

            destination.fill(ColorID.cast(0x7));

            destination.copy(&source, 4);
            const expected =
                \\7777
                \\7777
                \\7777
                \\7777
            ;

            try expectPixels(expected, destination);
        }

        test "loadBitmapResource correctly parses planar bitmap data" {
            const data = &planar_bitmap.Fixtures.valid_16px;
            const Buffer = Instance(4, 4);

            var buffer = Buffer{};
            try buffer.loadBitmapResource(data);

            const expected =
                \\1919
                \\5D5D
                \\E6E6
                \\A2A2
            ;

            try expectPixels(expected, buffer);
        }

        test "renderToSurface correctly renders 24-bit colors from specified palette" {
            const Buffer = Instance(4, 4);
            const DestinationSurface = Surface(4, 4);

            var source = Buffer{};
            var destination: DestinationSurface = undefined;

            source.fillFromString(
                \\FEDC
                \\BA98
                \\7654
                \\3210
            );

            const palette = PaletteFixtures.palette;
            const expected = DestinationSurface{
                palette[15],
                palette[14],
                palette[13],
                palette[12],
                palette[11],
                palette[10],
                palette[9],
                palette[8],
                palette[7],
                palette[6],
                palette[5],
                palette[4],
                palette[3],
                palette[2],
                palette[1],
                palette[0],
            };

            source.renderToSurface(&destination, palette);

            try testing.expectEqual(expected, destination);
        }
    };
}
