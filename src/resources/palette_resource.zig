//! This file defines a parser that extracts 16-color palettes from Another World's palette resource data.
//! Each game part stored its own set of 32 palettes in a single resource that contained 32 runs of 16
//! 2-byte values: one 2-byte value for each color, one 32-byte run for each palette,
//! 1024 bytes for each palette resource.
//!
//! (However, in the MS-DOS version at least, the palette files were actually 2048 bytes long:
//! The game stored palettes for VGA graphics in the first half, and downgraded palettes for EGA graphics
//! in the second half. For now we only read and use the VGA palettes. Reference:
//! https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/resource.h#L74)
//!
//! Each color was 12 bits: 4 bits each for red, green and blue. These mapped to the 12-bit
//! color space of the original Amiga hardware that the game was developed on, documented here:
//! http://fabiensanglard.net/another_world_polygons_amiga500/index.html

const Color = @import("../values/color.zig");
const Palette = @import("../values/palette.zig");
const PaletteID = @import("../values/palette_id.zig");

const static_limits = @import("../static_limits.zig");
const mem = @import("std").mem;

/// The number of palettes inside a palette resource.
const palette_count = static_limits.palette_count;

/// The size in bytes of an individual palette within an Another World palette resource.
pub const raw_palette_size = @sizeOf(Color.Raw) * static_limits.color_count; // 32 bytes

pub const Instance = struct {
    /// Raw palette data read from Another World's resource files.
    /// The instance does not own this data; the parent context must ensure
    /// the slice stays valid for as long as the instance is in scope.
    data: []const u8,

    const Self = @This();

    /// Returns the palette at the specified ID.
    /// Returns error.EndOfStream if the palette resource data was truncated.
    pub fn palette(self: Self, palette_id: PaletteID.Trusted) !Palette.Instance {
        const start = @as(usize, palette_id) * raw_palette_size;
        const end = start + raw_palette_size;

        if (end > self.data.len) return error.EndOfStream;
        // Palette colors are stored as 16-bit big-endian integers:
        // Reinterpret the slice of bytes for this palette as pairs of big and little bytes.
        // TODO: This could would probably be more readable if I used an I/O reader instead,
        // but I second-guessed the efficiency of the standard library's implementation of them.
        const raw_palette = @bitCast([]const [2]u8, self.data[start..end]);

        var pal: Palette.Instance = undefined;
        for (pal) |*color, index| {
            const raw_color = mem.readIntBig(Color.Raw, &raw_palette[index]);
            color.* = Color.parse(raw_color);
        }
        return pal;
    }
};

pub fn new(data: []const u8) Instance {
    return .{ .data = data };
}

pub const Error = error{
    EndOfStream,
};

// -- Examples --

pub const Fixtures = struct {
    // zig fmt: off
    const palette = [raw_palette_size]u8 {
        0x00, 0x00, // color 0
        0x01, 0x11, // color 1
        0x02, 0x22, // color 2
        0x03, 0x33, // color 3
        0x04, 0x44, // color 4
        0x05, 0x55, // color 5
        0x06, 0x66, // color 6
        0x07, 0x77, // color 7
        0x08, 0x88, // color 8
        0x09, 0x99, // color 9
        0x0A, 0xAA, // color 10
        0x0B, 0xBB, // color 11
        0x0C, 0xCC, // color 12
        0x0D, 0xDD, // color 13
        0x0E, 0xEE, // color 14
        0x0F, 0xFF, // color 15
    };
    // zig fmt: on

    pub const resource = palette ** palette_count;
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const fixedBufferStream = @import("std").io.fixedBufferStream;
const countingReader = @import("std").io.countingReader;

test "Instance.at returns expected palettes from resource" {
    // zig fmt: off
    const expected_palette = Palette.Instance {
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

    const data = &Fixtures.resource;
    const palettes = new(data);

    var idx: usize = 0;
    while (idx < palette_count) : (idx += 1) {
        const palette_id = @intCast(PaletteID.Trusted, idx);
        const palette = try palettes.palette(palette_id);

        try testing.expectEqualSlices(Color.Instance, &expected_palette, &palette);
    }
}

test "Instance.palette returns error.EndOfStream on truncated data" {
    const data = Fixtures.resource[0..1023];
    const palettes = new(data);

    try testing.expectError(error.EndOfStream, palettes.palette(31));
}
