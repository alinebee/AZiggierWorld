//! Tests that palettes are correctly parsed from Another World's original resource data.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const PaletteResource = @import("../resources/palette_resource.zig");
const ResourceDirectory = @import("../resources/resource_directory.zig");
const PaletteID = @import("../values/palette_id.zig");
const static_limits = @import("../static_limits.zig");

const validFixtureDir = @import("helpers.zig").validFixtureDir;

const testing = @import("../utils/testing.zig");

test "Parse all palettes in original game files" {
    var game_dir = validFixtureDir() catch return;
    defer game_dir.close();

    var resource_directory = try ResourceDirectory.new(&game_dir);
    const reader = resource_directory.reader();

    for (reader.resourceDescriptors()) |descriptor| {
        if (descriptor.type != .palettes) continue;

        const data = try reader.allocReadResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        const palettes = PaletteResource.new(data);

        var idx: usize = 0;
        while (idx < static_limits.palette_count) : (idx += 1) {
            const palette_id = @intCast(PaletteID.Trusted, idx);
            _ = try palettes.palette(palette_id);
        }
    }
}
