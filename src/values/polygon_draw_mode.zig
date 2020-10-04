const ColorID = @import("../values/color_id.zig");

/// A raw draw mode, stored in bytecode as an 8-bit unsigned integer.
pub const Raw = u8;

/// The possible modes in which a polygon can be rendered.
pub const Enum = union(enum(Raw)) {
    /// Render the polygon in a solid opaque color using the specified color index.
    solid_color: ColorID.Trusted,

    /// Remap the colors within the area of the polygon into their "highlighted" versions.
    /// This is used for translucency and lighting effects, like the ferrari headlights
    /// and particle accelerator flashes in the intro.
    /// See https://fabiensanglard.net/another_world_polygons/index.html for visual examples.
    highlight,

    /// Treat the polygon as a mask: fill it with pixels read from the corresponding
    /// location in another video buffer.
    /// This is likely used for foreground objects that occlude the player and enemies,
    /// but that were drawn into a background buffer.
    mask,
};

pub fn parse(raw: Raw) Enum {
    return switch (raw) {
        0...15 => |color_id| .{ .solid_color = @intCast(ColorID.Trusted, color_id) },
        16 => .highlight,
        // TODO: check if there's a specific constant the game always uses for mask.
        else => .mask,
    };
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "parse correctly parses raw draw mode" {
    var raw: u8 = 0;
    while (raw < 16) : (raw += 1) {
        const color_id = @intCast(ColorID.Trusted, raw);
        testing.expectEqual(.{ .solid_color = color_id }, parse(raw));
    }

    testing.expectEqual(.highlight, parse(16));
    testing.expectEqual(.mask, parse(17));
    testing.expectEqual(.mask, parse(255));
}
