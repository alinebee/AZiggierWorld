//! Tests that ResourceDirectory correctly parses real game files from the original Another World.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const anotherworld = @import("anotherworld");
const resources = anotherworld.resources;
const log = anotherworld.log;

const testing = @import("utils").testing;
const ensureValidFixtureDir = @import("helpers.zig").ensureValidFixtureDir;

test "ResourceDirectory reads all game resources" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try resources.ResourceDirectory.init(&game_dir);
    const reader = resource_directory.reader();

    const descriptors = reader.resourceDescriptors();
    try testing.expectEqual(146, descriptors.len);

    // For each resource, test that it can be parsed and decompressed without errors.
    for (descriptors) |descriptor, id| {
        switch (descriptor) {
            .empty => {
                log.warn("Skipping empty resource at {}", .{id});
                continue;
            },
            .valid => |valid_descriptor| {
                const data = try reader.allocReadResource(testing.allocator, valid_descriptor);
                defer testing.allocator.free(data);

                try testing.expectEqual(valid_descriptor.uncompressed_size, data.len);
            },
        }
    }
}

test "Instance.readResourceAlloc returns error.OutOfMemory if it runs out of memory when loading a non-empty resource" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try resources.ResourceDirectory.init(&game_dir);
    const reader = resource_directory.reader();

    const valid_descriptor = for (reader.resourceDescriptors()) |descriptor| {
        switch (descriptor) {
            .empty => continue,
            .valid => |valid| break valid,
        }
    } else {
        log.warn("\nNo non-empty resources found in game directory, skipping test. This probably indicates a corrupted version of the game.\n", .{});
        return;
    };

    try testing.expectError(
        error.OutOfMemory,
        reader.allocReadResource(testing.failing_allocator, valid_descriptor),
    );
}

test "Instance.allocReadResourceByID returns error.InvalidResourceID when given a resource ID that is out of range" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try resources.ResourceDirectory.init(&game_dir);
    const reader = resource_directory.reader();

    const invalid_id = resources.ResourceID.cast(@intCast(resources.ResourceID.Raw, reader.resourceDescriptors().len));
    try testing.expectError(
        error.InvalidResourceID,
        reader.allocReadResourceByID(testing.allocator, invalid_id),
    );
}
