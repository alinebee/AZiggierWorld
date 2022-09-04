const anotherworld = @import("../anotherworld.zig");
const rendering = anotherworld.rendering;
const static_limits = anotherworld.static_limits;
const text = anotherworld.text;
const vm = anotherworld.vm;

const mem = @import("std").mem;

/// The video subsystem responsible for handling draw calls and sending frames to the host screen.
pub const Video = struct {
    /// The type used for the video buffers.
    const Buffer = rendering.PackedBuffer(static_limits.virtual_screen_width, static_limits.virtual_screen_height);

    /// The resource from which part-specific polygon data will be read.
    polygons: rendering.PolygonResource,

    /// The resource from which global animation data will be read.
    animations: ?rendering.PolygonResource,

    /// The palettes used to render frames to the host screen.
    palettes: rendering.PaletteResource,

    /// The currently selected palette, loaded from `palettes` when `selectPalette` is called.
    /// Frames will be rendered to the host screen using this palette.
    /// This will be null when first created and after `setResourceLocations` has been called;
    /// The owning context must call `selectPalette` before attempting to call `renderBufferToSurface`.
    current_palette: ?rendering.Palette = null,

    /// The set of 4 buffers used for rendering.
    /// These will be filled with garbage data when the instance is first created;
    /// it is expected that the game program will initialize them with an explicit fill command.
    buffers: [static_limits.buffer_count]Buffer = .{.{}} ** static_limits.buffer_count,

    /// The index of the buffer in `buffers` that was rendered to the host screen on the previous frame.
    front_buffer_id: vm.BufferID.Specific = initial_front_buffer_id,

    /// The index of the buffer in `buffers` that will be rendered to the host screen on the next frame.
    back_buffer_id: vm.BufferID.Specific = initial_back_buffer_id,

    /// The index of the buffer in `buffers` that polygon and string drawing operations will draw into.
    /// (The reference implementation initialized this to the front buffer, not the back buffer:
    /// it's unclear why, as normally a game would want to send its draw operations to the back buffer.)
    target_buffer_id: vm.BufferID.Specific = initial_front_buffer_id,

    const initial_front_buffer_id: vm.BufferID.Specific = 2;
    const initial_back_buffer_id: vm.BufferID.Specific = 1;

    /// Masked drawing operations always read the mask from buffer 0,
    /// which presumably contains the scene background.
    pub const mask_buffer_id: vm.BufferID.Specific = 0;

    /// Bitmaps are always loaded into buffer 0, presumably replacing the scene background.
    pub const bitmap_buffer_id: vm.BufferID.Specific = 0;

    const Self = @This();

    // - Public methods -

    /// Called when a new game part is loaded to set the sources for polygon and palette data to new memory locations.
    pub fn setResourceLocations(self: *Self, palette_data: []const u8, polygon_data: []const u8, possible_animation_data: ?[]const u8) void {
        self.palettes = rendering.PaletteResource.init(palette_data);
        self.current_palette = null;

        self.polygons = rendering.PolygonResource.init(polygon_data);
        if (possible_animation_data) |animation_data| {
            self.animations = rendering.PolygonResource.init(animation_data);
        } else {
            self.animations = null;
        }
        // TODO: reset other aspects of the video state?
        // (If so, maybe we should just recreate the whole video instance?)
    }

    /// Select the palette used to render the next frame to the host screen.
    pub fn selectPalette(self: *Self, palette_id: rendering.PaletteID) !void {
        self.current_palette = try self.palettes.palette(palette_id);
    }

    /// Select the buffer that subsequent polygon and string draw operations will draw into.
    pub fn selectBuffer(self: *Self, buffer_id: vm.BufferID) void {
        self.target_buffer_id = self.resolvedBufferID(buffer_id);
    }

    /// Fill a video buffer with a solid color.
    pub fn fillBuffer(self: *Self, buffer_id: vm.BufferID, color: rendering.ColorID) ResolvedBufferID {
        const resolved_buffer_id = self.resolvedBufferID(buffer_id);
        self.buffers[resolved_buffer_id].fill(color);
        return resolved_buffer_id;
    }

    /// Copy the contents of one buffer into another at the specified vertical offset.
    /// Returns the ID of the buffer that was modified by the operation.
    /// Does nothing if the vertical offset is out of bounds.
    pub fn copyBuffer(self: *Self, source_id: vm.BufferID, destination_id: vm.BufferID, y: rendering.Point.Coordinate) ResolvedBufferID {
        const resolved_source_id = self.resolvedBufferID(source_id);
        const resolved_destination_id = self.resolvedBufferID(destination_id);

        self.buffers[resolved_destination_id].copy(&self.buffers[resolved_source_id], y);

        return resolved_destination_id;
    }

    /// Loads the specified bitmap resource into the default destination buffer for bitmaps.
    /// Returns the ID of the buffer that was modified by the operation.
    /// Returns an error if the specified bitmap data was the wrong size for the buffer.
    pub fn loadBitmapResource(self: *Self, bitmap_data: []const u8) !ResolvedBufferID {
        const buffer = &self.buffers[bitmap_buffer_id];
        try buffer.loadBitmapResource(bitmap_data);

        return bitmap_buffer_id;
    }

    /// Render a polygon from the specified source and address into the current target buffer,
    /// at the specified screen position and scale.
    /// Returns the ID of the buffer that was modified by the operation.
    /// Returns an error if the specified polygon address was invalid or if polygon data was malformed.
    pub fn drawPolygon(self: *Self, source: PolygonSource, address: rendering.PolygonResource.Address, point: rendering.Point, scale: rendering.PolygonScale) !ResolvedBufferID {
        const visitor = PolygonVisitor{
            .target_buffer = &self.buffers[self.target_buffer_id],
            .mask_buffer = &self.buffers[mask_buffer_id],
        };

        const resource = try self.resolvedPolygonSource(source);
        try resource.iteratePolygons(address, point, scale, visitor);

        return self.target_buffer_id;
    }

    /// Render a string from the English string table at the specified screen position
    /// in the specified color into the current target buffer.
    /// Returns the ID of the buffer that was modified by the operation.
    /// Returns an error if the string ID was not found or the string contained unsupported characters.
    pub fn drawString(self: *Self, string_id: text.StringID, color_id: rendering.ColorID, point: rendering.Point) !ResolvedBufferID {
        // TODO: allow different localizations at runtime.
        const string = try text.english.find(string_id);

        const buffer = &self.buffers[self.target_buffer_id];
        try rendering.drawString(Buffer, buffer, string, color_id, point);

        return self.target_buffer_id;
    }

    /// Set the specified buffer as the front buffer, marking that it is ready to draw to the host screen.
    /// If `.back_buffer` is specified, this will swap the front and back buffers.
    /// Returns the ID of the buffer that should be drawn to the host screen using `renderBufferToSurface`.
    pub fn markBufferAsReady(self: *Self, buffer_id: vm.BufferID) ResolvedBufferID {
        switch (buffer_id) {
            // When re-rendering the front buffer, leave the current front and back buffers as they were.
            .front_buffer => {},
            // When rendering the back buffer, swap the front and back buffers.
            .back_buffer => {
                mem.swap(vm.BufferID.Specific, &self.front_buffer_id, &self.back_buffer_id);
            },
            // When rendering a specific buffer by ID, mark that buffer as the front buffer
            // and leave the current back buffer alone.
            .specific => |resolved_id| {
                self.front_buffer_id = resolved_id;
            },
        }
        return self.front_buffer_id;
    }

    /// Render the contents of the specified buffer into the specified 24-bit host surface.
    /// Returns an error and leaves the surface unchanged if no palette has been chosen with `selectPalette` yet.
    pub fn renderBufferToSurface(self: Self, buffer_id: vm.BufferID.Specific, surface: *HostSurface) !void {
        if (self.current_palette) |palette| {
            self.buffers[buffer_id].renderToSurface(surface, palette);
        } else {
            return error.PaletteNotSelected;
        }
    }

    // - Private helpers -

    fn resolvedBufferID(self: Self, buffer_id: vm.BufferID) vm.BufferID.Specific {
        return switch (buffer_id) {
            .front_buffer => self.front_buffer_id,
            .back_buffer => self.back_buffer_id,
            .specific => |id| id,
        };
    }

    fn resolvedPolygonSource(self: Self, source: PolygonSource) !rendering.PolygonResource {
        switch (source) {
            .polygons => return self.polygons,
            .animations => return self.animations orelse error.AnimationsNotLoaded,
        }
    }

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

    /// The ID of one of the 4 buffers used by the rendering system.
    pub const ResolvedBufferID = vm.BufferID.Specific;

    /// The type of 24-bit buffer that hosts are expected to provide for the video subsystem to render frames into.
    pub const HostSurface = rendering.Surface(static_limits.virtual_screen_width, static_limits.virtual_screen_height);

    pub const Error = error{
        /// Attempted to render polygons from the animations resource when it was not loaded by the current game part.
        AnimationsNotLoaded,
        /// Attempted to render a buffer to a surface before selectPalette has been called.
        PaletteNotSelected,
    };
};

/// Used by `Video.drawPolygon` to loop over polygons parsed from a resource.
const PolygonVisitor = struct {
    /// The buffer to draw polygons into.
    target_buffer: *Video.Buffer,
    /// The buffer to read from when drawing masked polygons.
    mask_buffer: *const Video.Buffer,

    /// Draw a single polygon into the target buffer, using the mask buffer to read from if necessary.
    pub fn visit(self: @This(), polygon: rendering.Polygon) !void {
        try rendering.drawPolygon(Video.Buffer, self.target_buffer, self.mask_buffer, polygon);
    }
};

// -- Tests --

const testing = @import("utils").testing;
const Bitmap = rendering.IndexedBitmap(static_limits.virtual_screen_width, static_limits.virtual_screen_height);

test "Ensure everything compiles" {
    testing.refAllDecls(Video);
}

/// Construct a video instance populated with sample valid resource data,
/// with all buffers filled with color ID 0.
fn testInstance() Video {
    const polygon_data = &rendering.PolygonResource.Fixtures.resource;
    const palette_data = &rendering.PaletteResource.Fixtures.resource;

    var instance = Video{
        .polygons = rendering.PolygonResource.init(polygon_data),
        .animations = rendering.PolygonResource.init(polygon_data),
        .palettes = rendering.PaletteResource.init(palette_data),
    };

    for (instance.buffers) |*buffer| {
        buffer.fill(rendering.ColorID.cast(0x0));
    }

    return instance;
}

test "setResourceLocations sets resource data pointers and resets current palette" {
    var instance = testInstance();
    try instance.selectPalette(rendering.PaletteID.cast(0));

    const new_palette_data = [0]u8{};
    const new_polygon_data = [0]u8{};

    try testing.expect(instance.current_palette != null);
    instance.setResourceLocations(&new_palette_data, &new_polygon_data, null);

    try testing.expectEqual(null, instance.current_palette);
    try testing.expectEqual(&new_palette_data, instance.palettes.data);
    try testing.expectEqual(&new_polygon_data, instance.polygons.data);
    try testing.expectEqual(null, instance.animations);
}

test "resolvedBufferID returns expected IDs for each buffer enum" {
    const instance = testInstance();

    try testing.expectEqual(0, instance.resolvedBufferID(.{ .specific = 0 }));
    try testing.expectEqual(1, instance.resolvedBufferID(.{ .specific = 1 }));
    try testing.expectEqual(2, instance.resolvedBufferID(.{ .specific = 2 }));
    try testing.expectEqual(3, instance.resolvedBufferID(.{ .specific = 3 }));

    try testing.expectEqual(2, instance.front_buffer_id);
    try testing.expectEqual(2, instance.resolvedBufferID(.front_buffer));
    try testing.expectEqual(1, instance.back_buffer_id);
    try testing.expectEqual(1, instance.resolvedBufferID(.back_buffer));
}

test "resolvedPolygonSource with polygons resolves expected source" {
    const instance = testInstance();
    try testing.expectEqual(instance.polygons, try instance.resolvedPolygonSource(.polygons));
}

test "resolvedPolygonSource with animations resolves expected source when animations are loaded" {
    const instance = testInstance();
    try testing.expectEqual(instance.animations.?, try instance.resolvedPolygonSource(.animations));
}

test "resolvedPolygonSource with animations returns error when animations are not loaded" {
    var instance = testInstance();
    instance.animations = null;
    try testing.expectError(error.AnimationsNotLoaded, instance.resolvedPolygonSource(.animations));
}

test "markBufferAsReady with specific buffer sets front buffer while leaving back buffer alone" {
    const expected_buffer_id = 3;

    var instance = testInstance();
    const resolved_buffer_id = instance.markBufferAsReady(.{ .specific = expected_buffer_id });

    try testing.expectEqual(instance.front_buffer_id, resolved_buffer_id);
    try testing.expectEqual(expected_buffer_id, instance.front_buffer_id);
    try testing.expectEqual(Video.initial_back_buffer_id, instance.back_buffer_id);
}

test "markBufferAsReady swaps front and back buffers when back buffer is marked ready" {
    var instance = testInstance();
    const resolved_buffer_id = instance.markBufferAsReady(.back_buffer);

    try testing.expectEqual(instance.front_buffer_id, resolved_buffer_id);
    try testing.expectEqual(Video.initial_back_buffer_id, instance.front_buffer_id);
    try testing.expectEqual(Video.initial_front_buffer_id, instance.back_buffer_id);
}

test "markBufferAsReady does not swap buffers when front buffer is marked ready again" {
    var instance = testInstance();
    const resolved_buffer_id = instance.markBufferAsReady(.front_buffer);

    try testing.expectEqual(instance.front_buffer_id, resolved_buffer_id);
    try testing.expectEqual(Video.initial_front_buffer_id, instance.front_buffer_id);
    try testing.expectEqual(Video.initial_back_buffer_id, instance.back_buffer_id);
}

test "loadBitmapResource loads bitmap data into expected buffer" {
    var instance = testInstance();

    const bitmap_size = comptime rendering.planarBitmapDataSize(
        static_limits.virtual_screen_width,
        static_limits.virtual_screen_height,
    );
    const filled_bitmap_data = [_]u8{0xFF} ** bitmap_size;

    const expected_bitmap_buffer_contents = Bitmap.filled(rendering.ColorID.cast(0xF));
    const expected_untouched_buffer_contents = Bitmap.filled(rendering.ColorID.cast(0x0));

    const modified_buffer_id = try instance.loadBitmapResource(&filled_bitmap_data);
    try testing.expectEqual(Video.bitmap_buffer_id, modified_buffer_id);

    for (instance.buffers) |buffer, index| {
        const actual = buffer.toBitmap();
        if (index == Video.bitmap_buffer_id) {
            try rendering.expectEqualBitmaps(expected_bitmap_buffer_contents, actual);
        } else {
            try rendering.expectEqualBitmaps(expected_untouched_buffer_contents, actual);
        }
    }
}

test "selectPalette loads specified palette" {
    var instance = testInstance();

    const palette_id = rendering.PaletteID.cast(15);
    const expected_palette = try instance.palettes.palette(palette_id);

    try testing.expectEqual(null, instance.current_palette);
    try instance.selectPalette(palette_id);
    try testing.expectEqual(expected_palette, instance.current_palette);
}

test "selectPalette returns error and leaves current palette unchanged when palette data is corrupt" {
    const empty_palette_data = [0]u8{};

    var instance = testInstance();
    instance.palettes = rendering.PaletteResource.init(&empty_palette_data);

    try testing.expectEqual(null, instance.current_palette);
    try testing.expectError(error.EndOfStream, instance.selectPalette(rendering.PaletteID.cast(0)));
    try testing.expectEqual(null, instance.current_palette);
}

test "loadBitmapResource returns error from buffer when data is malformed" {
    var instance = testInstance();
    const empty_bitmap_data = [0]u8{};

    try testing.expectError(error.InvalidBitmapSize, instance.loadBitmapResource(&empty_bitmap_data));
}

test "renderBufferToSurface renders colors from current palette into surface" {
    const buffer_id = 0;
    const color_id = rendering.ColorID.cast(15);

    var instance = testInstance();
    try instance.selectPalette(rendering.PaletteID.cast(0));

    instance.buffers[buffer_id].fill(color_id);

    var surface: Video.HostSurface = undefined;
    const expected_color = instance.current_palette.?[color_id.index()];
    const expected_surface = rendering.filledSurface(Video.HostSurface, expected_color);

    try instance.renderBufferToSurface(buffer_id, &surface);
    try testing.expectEqual(expected_surface, surface);
}

test "renderBufferToSurface returns error.PaletteNotSelected and leaves surface unchanged if selectPalette has not been called" {
    const buffer_id = 0;

    var instance = testInstance();
    try testing.expectEqual(null, instance.current_palette);

    instance.buffers[buffer_id].fill(rendering.ColorID.cast(0));

    // This color is not present in the palette and should never be rendered normally
    const untouched_color = .{ .r = 1, .g = 2, .b = 3, .a = 0 };

    var surface = rendering.filledSurface(Video.HostSurface, untouched_color);
    const expected_surface = surface;

    try testing.expectError(error.PaletteNotSelected, instance.renderBufferToSurface(buffer_id, &surface));
    try testing.expectEqual(expected_surface, surface);
}
