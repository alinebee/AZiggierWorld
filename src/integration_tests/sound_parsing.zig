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
        switch (descriptor) {
            .empty => continue,
            .valid => |valid_descriptor| {
                if (valid_descriptor.type != .sound) continue;

                // Skip 0-length markers
                if (valid_descriptor.uncompressed_size == 0) {
                    log.info("Skipping 0-length file at {}", .{id});
                    continue;
                }

                const data = try reader.allocReadResource(testing.allocator, valid_descriptor);
                defer testing.allocator.free(data);

                const sound = try audio.SoundEffect.parse(data);
                if (sound.intro == null) {
                    if (sound.loop == null) {
                        log.info("Empty sound effect at {}", .{id});
                    } else {
                        log.info("Sound effect with no intro at {}", .{id});
                    }
                }
            },
        }
    }
}
