pub const ColorID = @import("rendering/color_id.zig").ColorID;
pub const Color = @import("rendering/color.zig").Color;

pub const PaletteID = @import("rendering/palette_id.zig").PaletteID;
pub const Palette = @import("rendering/palette.zig").Palette;
pub const PaletteResource = @import("rendering/palette_resource.zig").PaletteResource;

pub const Polygon = @import("rendering/polygon.zig").Polygon;
pub const PolygonResource = @import("rendering/polygon_resource.zig").PolygonResource;

pub const Point = @import("rendering/point.zig").Point;
pub const PolygonScale = @import("rendering/polygon_scale.zig").PolygonScale;

pub const PackedBuffer = @import("rendering/packed_buffer.zig").PackedBuffer;
pub const AlignedBuffer = @import("rendering/aligned_buffer.zig").AlignedBuffer;
pub const IndexedBitmap = @import("rendering/test_helpers/indexed_bitmap.zig").IndexedBitmap;
pub const expectEqualBitmaps = @import("rendering/test_helpers/indexed_bitmap.zig").expectEqualBitmaps;

pub const Surface = @import("rendering/surface.zig").Surface;
pub const filledSurface = @import("rendering/surface.zig").filledSurface;

pub const drawString = @import("rendering/draw_string.zig").drawString;
pub const drawPolygon = @import("rendering/draw_polygon.zig").drawPolygon;

pub const planarBitmapDataSize = @import("rendering/planar_bitmap.zig").bytesRequiredForSize;
