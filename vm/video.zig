//! Extends Machine.Instance with methods for rendering to the virtual screen.

const Machine = @import("machine.zig");
const Point = @import("types/point.zig");

/// Defines where to read polygon from for a polygon draw operation.
/// Another World's polygons may be stored in one of two locations:
/// - polygons: A game-part-specific resource containing scene backgrounds and incidental animations.
/// - animations: A shared resource containing common sprites like players, enemies, weapons etc.
pub const PolygonSource = enum {
    /// Draw polygon data from the currently-loaded polygon resource.
    polygons,
    /// Draw polygon data from the currently-loaded animation resource.
    animations,
};

/// The offset within a polygon or animation resource from which to read polygon data.
pub const PolygonAddress = u16;

/// The scale at which to render a polygon.
/// TODO: document the observed ranges and default value for this.
pub const PolygonScale = u8;

const log_unimplemented = @import("../utils/logging.zig").log_unimplemented;

/// Methods intended to be imported into Machine.Instance.
pub const Interface = struct {
    /// Render a polygon from the specified source and address at the specified screen position and scale.
    /// If scale is `null`, the polygon will be drawn at its default scale.
    /// Returns an error if the specified polygon address was invalid.
    pub fn drawPolygon(self: *Machine.Instance, source: PolygonSource, address: PolygonAddress, point: Point.Instance, scale: ?PolygonScale) !void {
        log_unimplemented("Video.drawPolygon: draw {}.{X} at x:{} y:{} scale:{}", .{
            @tagName(source),
            address,
            point.x,
            point.y,
            scale,
        });
    }
};
