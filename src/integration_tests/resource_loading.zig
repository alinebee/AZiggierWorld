//! Tests that ResourceDirectory correctly parses real game files from the original Another World.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const ResourceDirectory = @import("../resources/resource_directory.zig");
const ResourceID = @import("../values/resource_id.zig");

const testing = @import("../utils/testing.zig");
const validFixtureDir = @import("helpers.zig").validFixtureDir;

test "ResourceDirectory reads all game resources" {
    var game_dir = validFixtureDir() catch return;
    defer game_dir.close();

    const resource_directory = try ResourceDirectory.new(&game_dir);

    try testing.expectEqual(146, resource_directory.resourceDescriptors().len);

    // For each resource, test that it can be parsed and decompressed without errors.
    for (resource_directory.resourceDescriptors()) |descriptor| {
        const data = try resource_directory.allocReadResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        try testing.expectEqual(descriptor.uncompressed_size, data.len);
    }
}

test "Instance.readResourceAlloc returns error.OutOfMemory if it runs out of memory when loading a non-empty resource" {
    var game_dir = validFixtureDir() catch return;
    defer game_dir.close();

    const resource_directory = try ResourceDirectory.new(&game_dir);

    // Some resources are zero-length; testing.failing_allocator would not fail if the memory required is 0.
    const non_empty_descriptor = for (resource_directory.resourceDescriptors()) |descriptor| {
        if (descriptor.uncompressed_size > 0) {
            break descriptor;
        }
    } else {
        unreachable;
    };

    try testing.expectError(
        error.OutOfMemory,
        resource_directory.allocReadResource(testing.failing_allocator, non_empty_descriptor),
    );
}

test "Instance.allocReadResourceByID returns error.InvalidResourceID when given a resource ID that is out of range" {
    var game_dir = validFixtureDir() catch return;
    defer game_dir.close();

    const resource_directory = try ResourceDirectory.new(&game_dir);

    const invalid_id = @intCast(ResourceID.Raw, resource_directory.resourceDescriptors().len);
    try testing.expectError(
        error.InvalidResourceID,
        resource_directory.allocReadResourceByID(testing.allocator, invalid_id),
    );
}
