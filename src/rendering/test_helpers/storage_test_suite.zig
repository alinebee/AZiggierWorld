const expectBitmap = @import("indexed_bitmap.zig").expectBitmap;

// -- Test helpers --

/// Compare the contents of a storage buffer against an expected string.
pub fn expectPixels(expected: []const u8, actual: anytype) !void {
    const bitmap = actual.toBitmap();
    try expectBitmap(expected, bitmap);
}

// -- Tests --

/// Given a function that takes a width and height and constructs a buffer storage type,
/// runs a suite of tests against the public interface of that type.
/// Usage:
///   const storage_test_suite = @import("storage_test_suite.zig");
///
///   test "Run storage interface tests" {
///      storage_test_suite.runTests(FnThatReturnsStorageType);
///   }
pub fn runTests(comptime Instance: anytype) void {
    // Wrap the set of tests in a generic struct, where each test uses the specified storage constructor function.
    _ = struct {
        test "fill replaces all bytes in buffer with specified color" {
            var storage = Instance(4, 4){};
            const expected_before =
                \\0000
                \\0000
                \\0000
                \\0000
            ;

            try expectPixels(expected_before, storage);

            storage.fill(0xA);

            const expected_after =
                \\AAAA
                \\AAAA
                \\AAAA
                \\AAAA
            ;

            try expectPixels(expected_after, storage);
        }

        test "uncheckedDrawSpan with byte-aligned span sets solid color in slice" {
            comptime const Storage = Instance(10, 3);
            var storage = Storage{};

            const operation = Storage.DrawOperation.solidColor(0xD);

            storage.uncheckedDrawSpan(.{ .min = 2, .max = 7 }, 1, operation);

            const expected =
                \\0000000000
                \\00DDDDDD00
                \\0000000000
            ;
            try expectPixels(expected, storage);
        }

        test "uncheckedDrawSpan with non-byte-aligned start sets start pixel correctly" {
            comptime const Storage = Instance(10, 3);
            var storage = Storage{};

            const operation = Storage.DrawOperation.solidColor(0xC);

            storage.uncheckedDrawSpan(.{ .min = 1, .max = 7 }, 1, operation);

            const expected =
                \\0000000000
                \\0CCCCCCC00
                \\0000000000
            ;
            try expectPixels(expected, storage);
        }

        test "uncheckedDrawSpan with non-byte-aligned end sets end pixel correctly" {
            comptime const Storage = Instance(10, 3);
            var storage = Storage{};

            const operation = Storage.DrawOperation.solidColor(0x3);

            storage.uncheckedDrawSpan(.{ .min = 2, .max = 8 }, 1, operation);

            const expected =
                \\0000000000
                \\0033333330
                \\0000000000
            ;
            try expectPixels(expected, storage);
        }

        test "uncheckedDrawSpan with non-byte-aligned start and end sets start and end pixels correctly" {
            comptime const Storage = Instance(10, 3);
            var storage = Storage{};

            const operation = Storage.DrawOperation.solidColor(0x7);

            storage.uncheckedDrawSpan(.{ .min = 1, .max = 8 }, 1, operation);

            const expected =
                \\0000000000
                \\0777777770
                \\0000000000
            ;
            try expectPixels(expected, storage);
        }

        test "uncheckedDrawSpan highlights colors in slice" {
            comptime const Storage = Instance(16, 3);
            var storage = Storage{};
            storage.fillFromString(
                \\0123456789ABCDEF
                \\0123456789ABCDEF
                \\0123456789ABCDEF
            );

            const operation = Storage.DrawOperation.highlight();

            storage.uncheckedDrawSpan(.{ .min = 0, .max = 15 }, 1, operation);

            // Colors from 0-7 should have been ramped up to 8-F;
            // Colors from 8-F should have been left as they were.
            const expected =
                \\0123456789ABCDEF
                \\89ABCDEF89ABCDEF
                \\0123456789ABCDEF
            ;
            try expectPixels(expected, storage);
        }

        test "uncheckedDrawSpan replaces colors in slice with mask" {
            comptime const Storage = Instance(10, 3);
            var storage = Storage{};

            var mask_storage = Storage{};
            mask_storage.fillFromString(
                \\0123456789
                \\9876543210
                \\0123456789
            );

            const operation = Storage.DrawOperation.mask(&mask_storage);

            storage.uncheckedDrawSpan(.{ .min = 3, .max = 6 }, 1, operation);

            const expected =
                \\0000000000
                \\0006543000
                \\0000000000
            ;
            try expectPixels(expected, storage);
        }
    };
}