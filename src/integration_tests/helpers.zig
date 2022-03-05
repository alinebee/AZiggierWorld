const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const log = @import("../utils/logging.zig").log;

/// The path to the location you should put Another World game files to enable integration tests.
/// This is relative to the base project folder, not to the location of this source file.
pub const relative_fixture_path = "fixtures/dos/";

/// The name of a file that will be sniffed for in the fixture directory to determine
/// if it contains valid game files yet. Note that this is case sensitive.
pub const test_filename = "MEMLIST.BIN";

/// Validates that game files have been added to the fixture directory
/// and returns an open directory handle for it.
/// Caller owns the returned handle and must close it using fs.close().
/// If game files are missing, returns an error.
pub fn validFixtureDir() !fs.Dir {
    var dir = try fs.cwd().openDir(relative_fixture_path, .{});
    errdefer dir.close();

    // Test if MEMLIST.BIN exists in the fixture directory; if it does not,
    // the user hasn't populated the directory with game files yet.
    try dir.access(test_filename, .{});

    return dir;
}

/// Returns an open directory handle for the fixture directory,
/// or skips the current test if the necessary files are not available.
pub fn ensureValidFixtureDir() !fs.Dir {
    if (validFixtureDir()) |dir| {
        return dir;
    } else |err| {
        return switch (err) {
            error.FileNotFound => error.SkipZigTest,
            else => err,
        };
    }
}

// -- Tests --

test "Integration test fixture directory has been populated with game data" {
    var game_dir = validFixtureDir() catch |err| {
        if (err == error.FileNotFound) {
            log.warn("\nTo run integration tests, place the MEMLIST.BIN and BANK01-BANK0D files from an MS-DOS version of Another World into the {s} directory in the project root.\n", .{relative_fixture_path});
            return;
        } else {
            return err;
        }
    };
    defer game_dir.close();
}
