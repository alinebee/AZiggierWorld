const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const log = std.log;

// Relative to the base project folder, not to the location of this source file.
pub const relative_fixture_path = "fixtures/dos/";

/// Validates that game files have been added to the fixture directory and returns the path to them.
/// Caller owns the returned path and must free it using the same allocator.
/// If game files are missing, returns an error.
///
/// Intended usage:
/// const game_path = validFixturePath(testing.allocator) catch return;
pub fn validFixturePath(allocator: *mem.Allocator) ![]const u8 {
    const fixture_path = try fs.realpathAlloc(allocator, relative_fixture_path);
    errdefer allocator.free(fixture_path);

    const paths = [_][]const u8{ fixture_path, "MEMLIST.BIN" };
    const memlist_path = try fs.path.join(allocator, &paths);
    defer allocator.free(memlist_path);

    // Test if MEMLIST.BIN exists in the fixture directory;
    // if it does not, it means it hasn't been populated it with game files yet.
    try fs.cwd().access(memlist_path, .{ .read = true });

    return fixture_path;
}

// -- Tests --

const testing = std.testing;

test "Integration test fixture directory has been populated with game data" {
    const game_path = validFixturePath(testing.allocator) catch |err| {
        if (err == error.FileNotFound) {
            log.warn("\nTo run integration tests, place the MEMLIST.BIN and BANK01-BANK0D files from an MS-DOS version of Another World into the {s} directory in the project root.\n", .{relative_fixture_path});
            return;
        } else {
            return err;
        }
    };
    testing.allocator.free(game_path);
}
