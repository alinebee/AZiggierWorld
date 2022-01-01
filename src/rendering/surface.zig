const Color = @import("../values/color.zig");

/// Returns the type of a 24-bit rendering surface that has the specified width and height.
pub fn Instance(comptime width: usize, comptime height: usize) type {
    return [width * height]Color.Instance;
}
