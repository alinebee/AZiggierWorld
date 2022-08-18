//! Tests that palettes are correctly parsed from Another World's original resource data.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const PaletteResource = @import("../resources/palette_resource.zig").PaletteResource;
const ResourceDirectory = @import("../resources/resource_directory.zig").ResourceDirectory;
const PaletteID = @import("../values/palette_id.zig").PaletteID;

const ensureValidFixtureDir = @import("helpers.zig").ensureValidFixtureDir;

const anotherworld = @import("../lib/anotherworld.zig");
const static_limits = anotherworld.static_limits;
const testing = @import("utils").testing;

test "Parse all palettes in original game files" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try ResourceDirectory.init(&game_dir);
    const reader = resource_directory.reader();

    for (reader.resourceDescriptors()) |descriptor| {
        if (descriptor.type != .palettes) continue;

        const data = try reader.allocReadResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        const palettes = PaletteResource.init(data);

        var idx: usize = 0;
        while (idx < static_limits.palette_count) : (idx += 1) {
            const palette_id = PaletteID.cast(idx);
            _ = try palettes.palette(palette_id);
        }
    }
}
