//! Extends Machine.Instance with methods for rendering to the virtual screen.

const Machine = @import("machine.zig");
const Point = @import("../values/point.zig");
const ColorID = @import("../values/color_id.zig");
const StringID = @import("../values/string_id.zig");
const BufferID = @import("../values/buffer_id.zig");
const PaletteID = @import("../values/palette_id.zig");
const PolygonScale = @import("../values/polygon_scale.zig");
const Video = @import("../rendering/video.zig");

const english = @import("../assets/english.zig");

pub const PolygonSource = Video.PolygonSource;
pub const FrameDelay = Video.FrameDelay;
pub const PolygonAddress = @import("../resources/polygon_resource.zig").Address;

const log_unimplemented = @import("../utils/logging.zig").log_unimplemented;

/// Methods intended to be imported into Machine.Instance.
pub const Interface = struct {
    /// Render a polygon from the specified source and address at the specified screen position and scale.
    /// Returns an error if the specified polygon address was invalid.
    pub fn drawPolygon(self: *Machine.Instance, source: PolygonSource, address: PolygonAddress, point: Point.Instance, scale: PolygonScale.Raw) !void {
        log_unimplemented("Video.drawPolygon: draw {s}.{X} at x:{} y:{} scale:{}", .{
            @tagName(source),
            address,
            point.x,
            point.y,
            scale,
        });
    }

    /// Render a string from the current string table at the specified screen position in the specified color.
    /// Returns an error if the string could not be found.
    pub fn drawString(self: *Machine.Instance, string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
        log_unimplemented("Video.drawString: draw #{s} color:{} at x:{} y:{}", .{
            try english.find(string_id),
            color_id,
            point.x,
            point.y,
        });
    }

    /// Select the active palette to render the video buffer in.
    pub fn selectPalette(self: *Machine.Instance, palette_id: PaletteID.Trusted) void {
        log_unimplemented("Video.selectPalette: {}", .{palette_id});
    }

    /// Select the video buffer that subsequent drawPolygon and drawString operations will draw into.
    pub fn selectVideoBuffer(self: *Machine.Instance, buffer_id: BufferID.Enum) void {
        log_unimplemented("Video.selectVideoBuffer: {}", .{buffer_id});
    }

    /// Fill a specified video buffer with a single color.
    pub fn fillVideoBuffer(self: *Machine.Instance, buffer_id: BufferID.Enum, color_id: ColorID.Trusted) void {
        log_unimplemented("Video.fillVideoBuffer: {} color:{}", .{ buffer_id, color_id });
    }

    /// Copy the contents of one video buffer into another at the specified vertical offset.
    pub fn copyVideoBuffer(self: *Machine.Instance, source: BufferID.Enum, destination: BufferID.Enum, vertical_offset: Point.Coordinate) void {
        log_unimplemented("Video.copyVideoBuffer: source:{} destination:{} vertical_offset:{}", .{
            source,
            destination,
            vertical_offset,
        });
    }

    /// Render the contents of the specified buffer to the host screen after the specified delay.
    pub fn renderVideoBuffer(self: *Machine.Instance, buffer_id: BufferID.Enum, delay: FrameDelay) void {
        log_unimplemented("Video.renderVideoBuffer: {} delay:{}", .{
            buffer_id,
            delay,
        });
    }
};
