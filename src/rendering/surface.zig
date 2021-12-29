const Color = @import("../values/color.zig");
const static_limits = @import("../static_limits.zig");

/// A surface suitable for displaying Another World's 320x200 virtual screen buffers.
pub const Default = Instance(static_limits.virtual_screen_width, static_limits.virtual_screen_height);

/// Returns the type of a 24-bit rendering surface that has the specified width and height.
/// Intended for use in unit tests for buffers of arbitrary sizes; use `Default` instead.
pub fn Instance(comptime width: usize, comptime height: usize) type {
    return [width * height]Color.Instance;
}
