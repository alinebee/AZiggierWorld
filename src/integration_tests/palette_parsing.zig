//! Tests that palettes are correctly parsed from Another World's original resource data.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const anotherworld = @import("anotherworld");
const resources = anotherworld.resources;
const rendering = anotherworld.rendering;
const static_limits = anotherworld.static_limits;

const ensureValidFixtureDir = @import("helpers.zig").ensureValidFixtureDir;

const testing = @import("utils").testing;

test "Parse all palettes in original game files" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try resources.ResourceDirectory.init(&game_dir);
    const reader = resource_directory.reader();

    for (reader.resourceDescriptors()) |descriptor| {
        if (descriptor.type != .palettes) continue;

        const data = try reader.allocReadResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        const palettes = rendering.PaletteResource.init(data);

        var idx: usize = 0;
        while (idx < static_limits.palette_count) : (idx += 1) {
            const palette_id = rendering.PaletteID.cast(idx);
            _ = try palettes.palette(palette_id);
        }
    }
}
