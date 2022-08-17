const Color = @import("color.zig").Color;
const static_limits = @import("../../static_limits.zig");

/// The number of colors inside a palette.
const color_count = static_limits.color_count;

/// A 16-color palette of 24-bit colors.
pub const Palette = [color_count]Color;

pub const Fixtures = struct {
    // zig fmt: off

    /// A sample 16-color palette of 24-bit colors.
    pub const palette = Palette {
        .{ .r = 0,      .g = 0,     .b = 0, .a = 255 },    // color 0
        .{ .r = 16,     .g = 16,    .b = 16, .a = 255 },   // color 1
        .{ .r = 32,     .g = 32,    .b = 32, .a = 255 },   // color 2
        .{ .r = 48,     .g = 48,    .b = 48, .a = 255 },   // color 3
        .{ .r = 68,     .g = 68,    .b = 68, .a = 255 },   // color 4
        .{ .r = 84,     .g = 84,    .b = 84, .a = 255 },   // color 5
        .{ .r = 100,    .g = 100,   .b = 100, .a = 255 },  // color 6
        .{ .r = 116,    .g = 116,   .b = 116, .a = 255 },  // color 7
        .{ .r = 136,    .g = 136,   .b = 136, .a = 255 },  // color 8
        .{ .r = 152,    .g = 152,   .b = 152, .a = 255 },  // color 9
        .{ .r = 168,    .g = 168,   .b = 168, .a = 255 },  // color 10
        .{ .r = 184,    .g = 184,   .b = 184, .a = 255 },  // color 11
        .{ .r = 204,    .g = 204,   .b = 204, .a = 255 },  // color 12
        .{ .r = 220,    .g = 220,   .b = 220, .a = 255 },  // color 13
        .{ .r = 236,    .g = 236,   .b = 236, .a = 255 },  // color 14
        .{ .r = 252,    .g = 252,   .b = 252, .a = 255 },  // color 15
    };
    // zig fmt: on
};
