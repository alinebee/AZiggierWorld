const expectBitmap = @import("indexed_bitmap.zig").expectBitmap;

// -- Test helpers --

/// Compare the contents of a storage buffer against an expected string.
pub fn expectPixels(expected: []const u8, actual: anytype) void {
    const bitmap = actual.toBitmap();
    expectBitmap(expected, bitmap);
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

            expectPixels(expected_before, storage);

            storage.fill(0xA);

            const expected_after =
                \\AAAA
                \\AAAA
                \\AAAA
                \\AAAA
            ;

            expectPixels(expected_after, storage);
        }

        test "uncheckedSetNativeColor sets color at point" {
            comptime const Storage = Instance(4, 4);
            var storage = Storage{};

            storage.uncheckedSetNativeColor(.{ .x = 1, .y = 1 }, Storage.nativeColor(0x3));
            storage.uncheckedSetNativeColor(.{ .x = 2, .y = 1 }, Storage.nativeColor(0xE));
            storage.uncheckedSetNativeColor(.{ .x = 3, .y = 1 }, Storage.nativeColor(0x1));

            const expected =
                \\0000
                \\03E1
                \\0000
                \\0000
            ;
            expectPixels(expected, storage);
        }

        test "uncheckedDrawPixel sets solid color at point and ignores mask" {
            comptime const Storage = Instance(4, 4);
            var storage = Storage{};
            var mask_storage = Storage{};
            mask_storage.fill(0xF);

            storage.uncheckedDrawPixel(.{ .x = 2, .y = 2 }, .{ .solid_color = 0xD }, &mask_storage);
            storage.uncheckedDrawPixel(.{ .x = 3, .y = 0 }, .{ .solid_color = 0x7 }, &mask_storage);

            const expected =
                \\0007
                \\0000
                \\00D0
                \\0000
            ;
            expectPixels(expected, storage);
        }

        test "uncheckedDrawPixel highlights color at point and ignores mask" {
            comptime const Storage = Instance(4, 4);

            var storage = Storage.fromString(
                \\0000
                \\4567
                \\0000
                \\89AB
            );

            var mask_storage = Storage{};
            mask_storage.fill(0xF);

            storage.uncheckedDrawPixel(.{ .x = 0, .y = 1 }, .highlight, &mask_storage);
            storage.uncheckedDrawPixel(.{ .x = 1, .y = 1 }, .highlight, &mask_storage);
            storage.uncheckedDrawPixel(.{ .x = 2, .y = 1 }, .highlight, &mask_storage);
            storage.uncheckedDrawPixel(.{ .x = 3, .y = 1 }, .highlight, &mask_storage);

            storage.uncheckedDrawPixel(.{ .x = 0, .y = 3 }, .highlight, &mask_storage);
            storage.uncheckedDrawPixel(.{ .x = 1, .y = 3 }, .highlight, &mask_storage);
            storage.uncheckedDrawPixel(.{ .x = 2, .y = 3 }, .highlight, &mask_storage);
            storage.uncheckedDrawPixel(.{ .x = 3, .y = 3 }, .highlight, &mask_storage);

            // Colors from 0...7 should have been ramped up to 8...F;
            // colors from 8...F should have been left as they are.
            const expected =
                \\0000
                \\CDEF
                \\0000
                \\89AB
            ;
            expectPixels(expected, storage);
        }

        test "uncheckedDrawPixel copies color at point from mask" {
            comptime const Storage = Instance(4, 4);
            var storage = Storage{};

            var mask_storage = Storage{};
            mask_storage.fill(0xF);

            storage.uncheckedDrawPixel(.{ .x = 1, .y = 1 }, .mask, &mask_storage);

            const expected =
                \\0000
                \\0F00
                \\0000
                \\0000
            ;
            expectPixels(expected, storage);
        }

        test "uncheckedDrawSpan with byte-aligned span sets solid color in slice and ignores mask" {
            comptime const Storage = Instance(10, 3);
            var storage = Storage{};

            var mask_storage = Storage{};
            mask_storage.fill(0xF);

            storage.uncheckedDrawSpan(.{ .min = 2, .max = 7 }, 1, .{ .solid_color = 0xD }, &mask_storage);

            const expected =
                \\0000000000
                \\00DDDDDD00
                \\0000000000
            ;
            expectPixels(expected, storage);
        }

        test "uncheckedDrawSpan with non-byte-aligned start sets start pixel correctly" {
            comptime const Storage = Instance(10, 3);
            var storage = Storage{};

            var mask_storage = Storage{};
            mask_storage.fill(0xF);

            storage.uncheckedDrawSpan(.{ .min = 1, .max = 7 }, 1, .{ .solid_color = 0xC }, &mask_storage);

            const expected =
                \\0000000000
                \\0CCCCCCC00
                \\0000000000
            ;
            expectPixels(expected, storage);
        }

        test "uncheckedDrawSpan with non-byte-aligned end sets end pixel correctly" {
            comptime const Storage = Instance(10, 3);
            var storage = Storage{};

            var mask_storage = Storage{};
            mask_storage.fill(0xF);

            storage.uncheckedDrawSpan(.{ .min = 2, .max = 8 }, 1, .{ .solid_color = 3 }, &mask_storage);

            const expected =
                \\0000000000
                \\0033333330
                \\0000000000
            ;
            expectPixels(expected, storage);
        }

        test "uncheckedDrawSpan with non-byte-aligned start and end sets start and end pixels correctly" {
            comptime const Storage = Instance(10, 3);
            var storage = Storage{};

            var mask_storage = Storage{};
            mask_storage.fill(0xF);

            storage.uncheckedDrawSpan(.{ .min = 1, .max = 8 }, 1, .{ .solid_color = 0x7 }, &mask_storage);

            const expected =
                \\0000000000
                \\0777777770
                \\0000000000
            ;
            expectPixels(expected, storage);
        }

        test "uncheckedDrawSpan highlights colors in slice and ignores mask" {
            comptime const Storage = Instance(16, 3);
            var storage = Storage.fromString(
                \\0123456789ABCDEF
                \\0123456789ABCDEF
                \\0123456789ABCDEF
            );

            var mask_storage = Storage{};
            mask_storage.fill(0xF);

            storage.uncheckedDrawSpan(.{ .min = 0, .max = 15 }, 1, .highlight, &mask_storage);

            // Colors from 0-7 should have been ramped up to 8-F;
            // Colors from 8-F should have been left as they were.
            const expected =
                \\0123456789ABCDEF
                \\89ABCDEF89ABCDEF
                \\0123456789ABCDEF
            ;
            expectPixels(expected, storage);
        }

        test "uncheckedDrawSpan replaces colors in slice with mask" {
            comptime const Storage = Instance(10, 3);
            var storage = Storage{};

            var mask_storage = Storage.fromString(
                \\0123456789
                \\9876543210
                \\0123456789
            );

            storage.uncheckedDrawSpan(.{ .min = 3, .max = 6 }, 1, .mask, &mask_storage);

            const expected =
                \\0000000000
                \\0006543000
                \\0000000000
            ;
            expectPixels(expected, storage);
        }
    };
}
