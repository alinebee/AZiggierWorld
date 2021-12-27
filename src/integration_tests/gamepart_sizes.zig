//! This file dumps data about the sizes of each game part's data.
//! It does not test functionality and so is kept out of the main suite of integration tests.

const ResourceDirectory = @import("../resources/resource_directory.zig");
const ResourceDescriptor = @import("../resources/resource_descriptor.zig");
const GamePart = @import("../values/game_part.zig");

const validFixtureDir = @import("helpers.zig").validFixtureDir;
const debugPrint = @import("std").debug.print;
const testing = @import("../utils/testing.zig");
const math = @import("std").math;

test "Report sizes for each game part" {
    var game_dir = validFixtureDir() catch return;
    defer game_dir.close();

    var resource_directory = try ResourceDirectory.new(&game_dir);
    const reader = resource_directory.reader();

    var max_bytecode_size: usize = 0;
    var max_palettes_size: usize = 0;
    var max_polygons_size: usize = 0;
    var max_animations_size: usize = 0;

    for (GamePart.Enum.all) |part| {
        const resource_ids = part.resourceIDs();

        debugPrint("\nPart: {s}\n----\n", .{@tagName(part)});

        var total_size: usize = 0;
        const bytecode = try reader.resourceDescriptor(resource_ids.bytecode);
        debugPrint("bytecode: #{}, {} bytes\n", .{ resource_ids.bytecode, bytecode.uncompressed_size });
        total_size += bytecode.uncompressed_size;
        max_bytecode_size = math.max(max_bytecode_size, bytecode.uncompressed_size);

        const palettes = try reader.resourceDescriptor(resource_ids.palettes);
        debugPrint("palette: #{}, {} bytes\n", .{ resource_ids.palettes, palettes.uncompressed_size });
        total_size += palettes.uncompressed_size;
        max_palettes_size = math.max(max_palettes_size, palettes.uncompressed_size);

        const polygons = try reader.resourceDescriptor(resource_ids.polygons);
        debugPrint("polygons: #{}, {} bytes\n", .{ resource_ids.polygons, polygons.uncompressed_size });
        total_size += polygons.uncompressed_size;
        max_polygons_size = math.max(max_polygons_size, polygons.uncompressed_size);

        if (resource_ids.animations) |animation_id| {
            const animations = try reader.resourceDescriptor(animation_id);
            debugPrint("animations: #{}, {} bytes\n", .{ animation_id, animations.uncompressed_size });
            total_size += animations.uncompressed_size;
            max_animations_size = math.max(max_animations_size, animations.uncompressed_size);
        } else {
            debugPrint("animations: UNUSED\n", .{});
        }
        debugPrint("----\ntotal size: {} bytes\n", .{total_size});

        debugPrint("\n====\n", .{});
    }

    debugPrint("\nMax sizes:\n----\n", .{});
    debugPrint("bytecode: {} bytes\n", .{max_bytecode_size});
    debugPrint("palettes: {} bytes\n", .{max_palettes_size});
    debugPrint("polygons: {} bytes\n", .{max_polygons_size});
    debugPrint("animations: {} bytes\n", .{max_animations_size});

    const max_total_size = max_bytecode_size + max_palettes_size + max_polygons_size + max_animations_size;
    debugPrint("----\nmax possible size for game part: {} bytes\n\n", .{max_total_size});
}
