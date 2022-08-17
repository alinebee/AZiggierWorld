pub const ColorID = @import("rendering/color_id.zig").ColorID;
pub const Color = @import("rendering/color.zig").Color;
pub const Palette = @import("rendering/palette.zig").Palette;
pub const Polygon = @import("rendering/polygon.zig").Polygon;

pub const Point = @import("rendering/point.zig").Point;
pub const PolygonScale = @import("rendering/polygon_scale.zig").PolygonScale;
pub const DrawMode = @import("rendering/draw_mode.zig").DrawMode;

pub const PackedBuffer = @import("rendering/packed_buffer.zig").PackedBuffer;
pub const AlignedBuffer = @import("rendering/aligned_buffer.zig").AlignedBuffer;
pub const IndexedBitmap = @import("rendering/test_helpers/indexed_bitmap.zig").IndexedBitmap;
pub const expectEqualBitmaps = @import("rendering/test_helpers/indexed_bitmap.zig").expectEqualBitmaps;

pub const Surface = @import("rendering/surface.zig").Surface;
pub const filledSurface = @import("rendering/surface.zig").filledSurface;

pub const drawString = @import("rendering/draw_string.zig").drawString;
pub const drawPolygon = @import("rendering/draw_polygon.zig").drawPolygon;
