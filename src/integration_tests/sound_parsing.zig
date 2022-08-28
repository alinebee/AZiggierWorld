//! Tests that sound effects are correctly parsed from Another World's original resource data.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const anotherworld = @import("anotherworld");
const audio = anotherworld.audio;
const resources = anotherworld.resources;
const log = anotherworld.log;

const ensureValidFixtureDir = @import("helpers.zig").ensureValidFixtureDir;

const testing = @import("utils").testing;

test "Parse all sound effects in original game files" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try resources.ResourceDirectory.init(&game_dir);
    const reader = resource_directory.reader();

    // Uncomment to print out statistics
    @import("std").testing.log_level = .debug;

    for (reader.resourceDescriptors()) |descriptor, id| {
        if (descriptor.type != .sound_or_empty) continue;

        const data = try reader.allocReadResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        if (audio.SoundEffect.parse(data)) |sound| {
            if (sound.intro == null) {
                if (sound.loop == null) {
                    log.debug("Empty sound effect at {}", .{id});
                } else {
                    log.debug("Sound effect with no intro at {}", .{id});
                }
            }
        } else |err| {
            if (err == error.TruncatedData and data.len == 0) {
                log.debug("0-length sound effect at {}", .{id});
            } else {
                return err;
            }
        }
    }
}