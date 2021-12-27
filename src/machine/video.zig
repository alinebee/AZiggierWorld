const Point = @import("../values/point.zig");
const ColorID = @import("../values/color_id.zig");
const StringID = @import("../values/string_id.zig");
const BufferID = @import("../values/buffer_id.zig");
const PaletteID = @import("../values/palette_id.zig");
const PolygonScale = @import("../values/polygon_scale.zig");
const PolygonResource = @import("../resources/polygon_resource.zig");
const PaletteResource = @import("../resources/palette_resource.zig");
const Polygon = @import("../rendering/polygon.zig");
const VideoBuffer = @import("../rendering/video_buffer.zig");
const PackedStorage = @import("../rendering/storage/packed_storage.zig");

const static_limits = @import("../static_limits.zig");

const english = @import("../assets/english.zig");

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

/// A length of time in milliseconds to leave a frame on screen.
pub const Milliseconds = usize;

/// The location of a polygon record within its containing resource.
pub const PolygonAddress = PolygonResource.Address;

/// The type used for buffer storage.
pub const Buffer = VideoBuffer.Instance(PackedStorage.Instance, static_limits.virtual_screen_width, static_limits.virtual_screen_height);

/// The video subsystem responsible for handling draw calls and sending frames to the host screen.
pub const Instance = struct {
    /// The resource from which part-specific polygon data will be read.
    polygons: PolygonResource.Instance,

    /// The resource from which global animation data will be read.
    animations: ?PolygonResource.Instance,

    /// The palettes used to render frames to the host screen.
    palettes: PaletteResource.Instance,

    /// The set of 4 buffers used for rendering.
    /// These will be filled with garbage data when the instance is first created;
    /// it is expected that the game program will initialize them with an explicit fill command.
    buffers: [static_limits.buffer_count]Buffer = .{.{}} ** static_limits.buffer_count,

    /// The index of the currently selected palette in `palette_resource`.
    /// Frames will be rendered to the host screen using this palette.
    palette_id: PaletteID.Trusted = 0,

    /// The index of the buffer in `buffers` that draw instructions will render into.
    target_buffer_id: BufferID.Specific = 2,

    /// The index of the buffer in `buffers` that will be rendered to the host screen on the next frame.
    back_buffer_id: BufferID.Specific = 1,

    /// The index of the buffer in `buffers` that was rendered to the host screen on the previous frame.
    front_buffer_id: BufferID.Specific = 2,

    /// Masked drawing operations always read the mask from buffer 0.
    pub const mask_buffer_id: BufferID.Specific = 0;

    /// Bitmaps are always loaded into buffer 0.
    pub const bitmap_buffer_id: BufferID.Specific = 0;

    const Self = @This();

    // - Public methods -

    /// Called when a new game part is loaded to set the sources for polygon and palette data to new memory locations.
    pub fn setResourceLocations(self: *Self, palettes: []const u8, polygons: []const u8, possible_animations: ?[]const u8) void {
        self.palettes = PaletteResource.new(palettes);
        self.polygons = PolygonResource.new(polygons);
        if (possible_animations) |animations| {
            self.animations = PolygonResource.new(animations);
        } else {
            self.animations = null;
        }
        // TODO: reset other aspects of the video state?
        // (If so, maybe we should just recreate the whole video instance?)
    }

    /// Select the palette used to render the next frame to the host screen.
    pub fn selectPalette(self: *Self, palette_id: PaletteID.Trusted) void {
        self.palette_id = palette_id;
    }

    /// Select the buffer that subsequent polygon and string draw operations will draw into.
    pub fn selectBuffer(self: *Self, buffer_id: BufferID.Enum) void {
        self.target_buffer_id = self.resolvedBufferID(buffer_id);
    }

    /// Fill a video buffer with a solid color.
    pub fn fillBuffer(self: *Self, buffer_id: BufferID.Enum, color: ColorID.Trusted) void {
        var buffer = self.resolvedBuffer(buffer_id);
        buffer.fill(color);
    }

    /// Copy the contents of one buffer into another at the specified vertical offset.
    /// Does nothing if the vertical offset is out of bounds.
    pub fn copyBuffer(self: *Self, source_id: BufferID.Enum, destination_id: BufferID.Enum, y: Point.Coordinate) void {
        const source = self.resolvedBuffer(source_id);
        var destination = self.resolvedBuffer(destination_id);

        destination.copy(source, y);
    }

    /// Loads the specified bitmap resource into the default destination buffer for bitmaps.
    /// Returns an error if the specified bitmap data was the wrong size for the buffer.
    pub fn loadBitmapResource(self: *Self, bitmap_data: []const u8) !void {
        var buffer = &self.buffers[bitmap_buffer_id];
        try buffer.loadBitmapResource(bitmap_data);
    }

    /// Render a polygon from the specified source and address at the specified screen position and scale.
    /// Returns an error if the specified polygon address was invalid or if polygon data was malformed.
    pub fn drawPolygon(self: *Self, source: PolygonSource, address: PolygonResource.Address, point: Point.Instance, scale: PolygonScale.Raw) !void {
        const visitor = PolygonVisitor{
            .target_buffer = &self.buffers[self.target_buffer_id],
            .mask_buffer = &self.buffers[mask_buffer_id],
        };

        const resource = try self.resolvedPolygonSource(source);
        try resource.iteratePolygons(address, point, scale, visitor);
    }

    /// Render a string from the English string table at the specified screen position
    /// in the specified color. Returns an error if the string ID was not found
    /// or the string contained unsupported characters.
    pub fn drawString(self: *Self, string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
        var buffer = &self.buffers[self.target_buffer_id];

        // TODO: allow different localizations at runtime.
        const string = try english.find(string_id);

        try buffer.drawString(string, color_id, point);
    }

    /// Render the contents of a video buffer to the host screen using the current palette.
    pub fn renderBuffer(self: *Self, buffer_id: BufferID.Enum, delay: Milliseconds, host: anytype) void {
        const resolved_id = self.resolvedBufferID(buffer_id);
        const buffer = &self.buffers[resolved_id];

        const palette = self.palettes[self.palette_id];
        var surface = host.getRenderSurface();
        buffer.renderIntoSurface(surface, palette);

        if (resolved_id != self.front_buffer_id) {
            self.back_buffer_id = self.front_buffer_id;
            self.front_buffer_id = resolved_id;
        }

        host.surfaceIsReady(surface, delay);
    }

    // - Private helpers -

    fn resolvedBufferID(self: Self, buffer_id: BufferID.Enum) BufferID.Specific {
        return switch (buffer_id) {
            .front_buffer => self.front_buffer_id,
            .back_buffer => self.back_buffer_id,
            .specific => |id| id,
        };
    }

    fn resolvedBuffer(self: *Self, buffer_id: BufferID.Enum) *Buffer {
        return &self.buffers[self.resolvedBufferID(buffer_id)];
    }

    fn resolvedPolygonSource(self: *Self, source: PolygonSource) !*PolygonResource.Instance {
        switch (source) {
            .polygons => return &self.polygons,
            .animations => {
                if (self.animations) |*resource| {
                    return resource;
                } else {
                    return error.AnimationsNotLoaded;
                }
            },
        }
    }
};

pub const Error = error{
    /// Attempted to render polygons from the animation when it was not loaded by the current game part.
    AnimationsNotLoaded,
};

/// Used by `Instance.drawPolygon` to loop over polygons parsed from a resource.
const PolygonVisitor = struct {
    /// The buffer to draw polygons into.
    target_buffer: *Buffer,
    /// The buffer to read from when drawing masked polygons.
    mask_buffer: *const Buffer,

    /// Draw a single polygon into the target buffer, using the mask buffer to read from if necessary.
    pub fn visit(self: @This(), polygon: Polygon.Instance) !void {
        try self.target_buffer.drawPolygon(polygon, self.mask_buffer);
    }
};

// -- Tests --

const testing = @import("std").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(Instance);
}
