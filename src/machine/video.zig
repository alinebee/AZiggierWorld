const Point = @import("../values/point.zig");
const ColorID = @import("../values/color_id.zig");
const StringID = @import("../values/string_id.zig");
const BufferID = @import("../values/buffer_id.zig");
const PaletteID = @import("../values/palette_id.zig");
const PolygonScale = @import("../values/polygon_scale.zig");
const PolygonResource = @import("../resources/polygon_resource.zig");
const PaletteResource = @import("../resources/palette_resource.zig");
const Polygon = @import("../rendering/polygon.zig");

const PackedStorage = @import("../rendering/storage/packed_storage.zig");
const drawPolygonImpl = @import("../rendering/operations/draw_polygon.zig").drawPolygon;
const drawStringImpl = @import("../rendering/operations/draw_string.zig").drawString;
const Host = @import("host.zig");

const static_limits = @import("../static_limits.zig");

const english = @import("../assets/english.zig");

const mem = @import("std").mem;

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

/// The type used for the video buffers.
const Buffer = PackedStorage.Instance(static_limits.virtual_screen_width, static_limits.virtual_screen_height);

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

    /// The index of the buffer in `buffers` that was rendered to the host screen on the previous frame.
    front_buffer_id: BufferID.Specific = initial_front_buffer_id,

    /// The index of the buffer in `buffers` that will be rendered to the host screen on the next frame.
    back_buffer_id: BufferID.Specific = initial_back_buffer_id,

    /// The index of the buffer in `buffers` that draw operations will draw into.
    /// (The reference implementation initialized this to the front buffer, not the back buffer:
    /// it's unclear why, as normally a game would want to send its draw operations to the back buffer.)
    target_buffer_id: BufferID.Specific = initial_front_buffer_id,

    const initial_front_buffer_id: BufferID.Specific = 2;
    const initial_back_buffer_id: BufferID.Specific = 1;

    /// Masked drawing operations always read the mask from buffer 0,
    /// which presumably contains the scene background.
    pub const mask_buffer_id: BufferID.Specific = 0;

    /// Bitmaps are always loaded into buffer 0, presumably replacing the scene background.
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

    /// Render a polygon from the specified source and address into the current target buffer,
    /// at the specified screen position and scale.
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
    /// in the specified color into the current target buffer.
    /// Returns an error if the string ID was not found or the string contained unsupported characters.
    pub fn drawString(self: *Self, string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
        var buffer = &self.buffers[self.target_buffer_id];

        // TODO: allow different localizations at runtime.
        const string = try english.find(string_id);

        try drawStringImpl(Buffer, buffer, string, color_id, point);
    }

    /// Render the contents of a video buffer to the host using the current palette.
    pub fn renderBuffer(self: *Self, buffer_id: BufferID.Enum, delay: Milliseconds, host: Host.Interface) !void {
        const buffer = self.resolvedBuffer(buffer_id);
        const palette = try self.palettes.palette(self.palette_id);

        var surface = try host.prepareSurface();
        buffer.renderToSurface(surface, palette);

        switch (buffer_id) {
            // When re-rendering the front buffer, leave the current front and back buffers as they were.
            .front_buffer => {},
            // When rendering the back buffer, swap the front and back buffers.
            .back_buffer => {
                mem.swap(BufferID.Specific, &self.front_buffer_id, &self.back_buffer_id);
            },
            // When rendering a specific buffer by ID, mark that buffer as the front buffer
            // and leave the current back buffer alone.
            .specific => |resolved_id| {
                self.front_buffer_id = resolved_id;
            },
        }

        host.surfaceReady(surface, delay);
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

    fn resolvedPolygonSource(self: *const Self, source: PolygonSource) !*const PolygonResource.Instance {
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
    /// Attempted to render polygons from the animations resource when it was not loaded by the current game part.
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
        try drawPolygonImpl(Buffer, self.target_buffer, self.mask_buffer, polygon);
    }
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const MockHost = @import("test_helpers/mock_host.zig");
const Color = @import("../values/color.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(Instance);
}

/// Construct a video instance populated with sample valid resource data,
/// with all buffers filled with color ID 0.
fn testInstance() Instance {
    const polygon_data = &PolygonResource.DataExamples.resource;
    const palette_data = &PaletteResource.DataExamples.resource;

    var instance = Instance{
        .polygons = PolygonResource.new(polygon_data),
        .animations = PolygonResource.new(polygon_data),
        .palettes = PaletteResource.new(palette_data),
    };

    for (instance.buffers) |*buffer| {
        buffer.fill(0x0);
    }

    return instance;
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
    try testing.expectEqual(&instance.polygons, try instance.resolvedPolygonSource(.polygons));
}

test "resolvedPolygonSource with animations resolves expected source when animations are loaded" {
    const instance = testInstance();
    try testing.expectEqual(&instance.animations.?, try instance.resolvedPolygonSource(.animations));
}

test "resolvedPolygonSource with animations returns error when animations are not loaded" {
    var instance = testInstance();
    instance.animations = null;
    try testing.expectError(error.AnimationsNotLoaded, instance.resolvedPolygonSource(.animations));
}

test "renderBuffer renders specific buffer to host surface and marks it as the front buffer" {
    var instance = testInstance();
    var test_host = MockHost.Instance.init(null);
    mem.set(Color.Instance, &test_host.surface, .{ .r = 255, .g = 255, .b = 255 });

    const expected_palette = try instance.palettes.palette(instance.palette_id);
    // All buffers of the test instance are filled with color ID 0.
    const expected_color = expected_palette[0];
    var expected_surface: Host.Surface = undefined;
    mem.set(Color.Instance, &expected_surface, expected_color);

    const buffer_to_render = 0;
    try instance.renderBuffer(BufferID.Enum{ .specific = buffer_to_render }, 0, test_host.host());

    try testing.expectEqual(1, test_host.call_counts.prepareSurface);
    try testing.expectEqual(1, test_host.call_counts.surfaceReady);
    try testing.expectEqual(expected_surface, test_host.surface);

    try testing.expectEqual(buffer_to_render, instance.front_buffer_id);
    try testing.expectEqual(Instance.initial_back_buffer_id, instance.back_buffer_id);
}

test "renderBuffer swaps front and back buffers when back buffer is rendered" {
    var instance = testInstance();
    var test_host = MockHost.Instance.init(null);

    try instance.renderBuffer(.back_buffer, 0, test_host.host());

    // Rendering should swap the front and back buffers
    try testing.expectEqual(Instance.initial_back_buffer_id, instance.front_buffer_id);
    try testing.expectEqual(Instance.initial_front_buffer_id, instance.back_buffer_id);
}

test "renderBuffer does not swap buffers when front buffer is re-rendered" {
    var instance = testInstance();
    var test_host = MockHost.Instance.init(null);

    try instance.renderBuffer(.front_buffer, 0, test_host.host());

    try testing.expectEqual(Instance.initial_front_buffer_id, instance.front_buffer_id);
    try testing.expectEqual(Instance.initial_back_buffer_id, instance.back_buffer_id);
}

test "renderBuffer returns host error and does not swap buffers when host is unable to create surface" {
    var instance = testInstance();
    var test_host = MockHost.Instance.init(error.CannotCreateSurface);

    try testing.expectError(error.CannotCreateSurface, instance.renderBuffer(.back_buffer, 0, test_host.host()));
    try testing.expectEqual(1, test_host.call_counts.prepareSurface);
    try testing.expectEqual(0, test_host.call_counts.surfaceReady);
    try testing.expectEqual(Instance.initial_front_buffer_id, instance.front_buffer_id);
    try testing.expectEqual(Instance.initial_back_buffer_id, instance.back_buffer_id);
}

test "renderBuffer returns error.EndOfStream and does not swap buffers or request surface when palette data was corrupted" {
    var instance = testInstance();
    const empty_palette_data = [0]u8{};
    instance.palettes = PaletteResource.new(&empty_palette_data);

    var test_host = MockHost.Instance.init(null);

    try testing.expectError(error.EndOfStream, instance.renderBuffer(.back_buffer, 0, test_host.host()));
    try testing.expectEqual(0, test_host.call_counts.prepareSurface);
    try testing.expectEqual(0, test_host.call_counts.surfaceReady);
    try testing.expectEqual(Instance.initial_front_buffer_id, instance.front_buffer_id);
    try testing.expectEqual(Instance.initial_back_buffer_id, instance.back_buffer_id);
}
