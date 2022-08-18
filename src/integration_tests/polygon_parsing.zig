//! Looks up polygon draw instructions from bytecode and tests that the corresponding
//! polygon addresses can be parsed from Another World's original resource data.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const anotherworld = @import("anotherworld");
const std = @import("std");

const Instruction = anotherworld.instructions.Instruction;
const Polygon = anotherworld.rendering.Polygon;
const PolygonScale = anotherworld.rendering.PolygonScale;
const Point = anotherworld.rendering.Point;

const Program = @import("../machine/program.zig").Program;
const PolygonResource = @import("../resources/polygon_resource.zig").PolygonResource;
const ResourceDirectory = @import("../resources/resource_directory.zig").ResourceDirectory;
const GamePart = @import("../values/game_part.zig").GamePart;

const testing = @import("utils").testing;
const log = anotherworld.log;
const ensureValidFixtureDir = @import("helpers.zig").ensureValidFixtureDir;

const PolygonDrawInstruction = union(enum) {
    background: Instruction.DrawBackgroundPolygon,
    sprite: Instruction.DrawSpritePolygon,
};

/// Parses an Another World bytecode program to find all the draw instructions in it.
/// Returns an array of draw instructions which is owned by the caller.
/// Returns an error if parsing or memory allocation failed.
fn findPolygonDrawInstructions(allocator: std.mem.Allocator, bytecode: []const u8) ![]const PolygonDrawInstruction {
    var draw_instructions = std.ArrayList(PolygonDrawInstruction).init(allocator);
    errdefer draw_instructions.deinit();

    var program = try Program.init(bytecode);
    while (program.isAtEnd() == false) {
        switch (try Instruction.parse(&program)) {
            .DrawBackgroundPolygon => |instruction| {
                try draw_instructions.append(.{ .background = instruction });
            },
            .DrawSpritePolygon => |instruction| {
                try draw_instructions.append(.{ .sprite = instruction });
            },
            else => {},
        }
    }

    return draw_instructions.toOwnedSlice();
}

/// Parses all polygon draw instructions from the bytecode for a given game part,
/// then parses the polygons themselves from the respective polygon or animation resource for that game part.
/// Returns the total number of polygons parsed, or an error if parsing or memory allocation failed.
fn parsePolygonInstructionsForGamePart(allocator: std.mem.Allocator, resource_directory: *ResourceDirectory, game_part: GamePart) !usize {
    const resource_ids = game_part.resourceIDs();
    const reader = resource_directory.reader();

    const bytecode = try reader.allocReadResourceByID(allocator, resource_ids.bytecode);
    defer allocator.free(bytecode);

    const draw_instructions = try findPolygonDrawInstructions(allocator, bytecode);
    defer allocator.free(draw_instructions);

    const polygons = PolygonResource.init(try reader.allocReadResourceByID(allocator, resource_ids.polygons));
    defer allocator.free(polygons.data);

    const maybe_animations: ?PolygonResource = init: {
        if (resource_ids.animations) |id| {
            const data = try reader.allocReadResourceByID(allocator, id);
            break :init PolygonResource.init(data);
        } else {
            break :init null;
        }
    };

    defer {
        if (maybe_animations) |animations| {
            allocator.free(animations.data);
        }
    }

    var visitor = PolygonVisitor{};

    // TODO: execute draw instructions directly on a virtual machine to trigger real polygon parsing and drawing.
    for (draw_instructions) |background_or_sprite| {
        switch (background_or_sprite) {
            .background => |instruction| {
                try polygons.iteratePolygons(instruction.address, instruction.point, .default, &visitor);
            },
            .sprite => |instruction| {
                const resource = switch (instruction.source) {
                    .polygons => polygons,
                    .animations => maybe_animations orelse return error.MissingAnimationsBlock,
                };
                // Don't bother parsing the scale or origin from the original sprite instruction.
                const origin = Point{ .x = 160, .y = 100 };

                try resource.iteratePolygons(instruction.address, origin, .default, &visitor);
            },
        }
    }

    return visitor.count;
}

const Error = error{
    /// A game part's draw instructions tried to draw polygon data from the `animations` block
    /// when one is not defined for that game part.
    MissingAnimationsBlock,
};

const PolygonVisitor = struct {
    count: usize = 0,

    pub fn visit(self: *PolygonVisitor, polygon: Polygon) !void {
        self.count += 1;
        try polygon.validate();
    }
};

test "Parse polygon instructions for every game part" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try ResourceDirectory.init(&game_dir);

    var count: usize = 0;
    for (GamePart.all) |game_part| {
        count += try parsePolygonInstructionsForGamePart(testing.allocator, &resource_directory, game_part);
    }

    log.info("\n{} polygon(s) successfully parsed.\n", .{count});
}
