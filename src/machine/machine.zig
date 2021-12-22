const ThreadID = @import("../values/thread_id.zig");
const BufferID = @import("../values/buffer_id.zig");
const ResourceID = @import("../values/resource_id.zig");
const StringID = @import("../values/string_id.zig");
const PaletteID = @import("../values/palette_id.zig");
const ColorID = @import("../values/color_id.zig");
const Channel = @import("../values/channel.zig");
const Point = @import("../values/point.zig");
const PolygonScale = @import("../values/polygon_scale.zig");
const Register = @import("../values/register.zig");
const GamePart = @import("../values/game_part.zig");

const Thread = @import("thread.zig");
const Stack = @import("stack.zig");
const Program = @import("program.zig");
const Video = @import("video.zig");
const Audio = @import("audio.zig");

const static_limits = @import("../static_limits.zig");

const log_unimplemented = @import("../utils/logging.zig").log_unimplemented;

const register_count = static_limits.register_count;
pub const Registers = [register_count]Register.Signed;

const thread_count = static_limits.thread_count;
pub const Threads = [thread_count]Thread.Instance;

pub const Instance = struct {
    /// The current state of the VM's 64 threads.
    threads: Threads,

    /// The current state of the VM's 256 registers.
    registers: Registers,

    /// The current program execution stack.
    stack: Stack.Instance,

    /// The currently-running program.
    program: Program.Instance,

    const Self = @This();

    // -- Resource subsystem interface --

    /// Load the resources for the specified game part and begin executing its program.
    /// Returns an error if one or more resources do not exist or could not be loaded.
    pub fn startGamePart(_: *Self, game_part: GamePart.Enum) !void {
        log_unimplemented("Resources.startGamePart: load game part {s}", .{@tagName(game_part)});
    }

    /// Load the specified resource if it is not already loaded.
    /// Returns an error if the specified resource ID does not exist or could not be loaded.
    pub fn loadResource(_: *Self, resource_id: ResourceID.Raw) !void {
        log_unimplemented("Resources.loadResource: load #{X}", .{resource_id});
    }

    /// Unload all resources and stop any currently-playing sound.
    pub fn unloadAllResources(_: *Self) void {
        log_unimplemented("Resources.unloadAllResources: unload all resources", .{});
    }

    // -- Video subsystem interface --

    /// Render a polygon from the specified source and address at the specified screen position and scale.
    /// Returns an error if the specified polygon address was invalid.
    pub fn drawPolygon(_: *Self, source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: PolygonScale.Raw) !void {
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
    pub fn drawString(_: *Self, string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
        log_unimplemented("Video.drawString: draw #{} color:{} at x:{} y:{}", .{
            string_id,
            color_id,
            point.x,
            point.y,
        });
    }

    /// Select the active palette to render the video buffer in.
    pub fn selectPalette(_: *Self, palette_id: PaletteID.Trusted) void {
        log_unimplemented("Video.selectPalette: {}", .{palette_id});
    }

    /// Select the video buffer that subsequent drawPolygon and drawString operations will draw into.
    pub fn selectVideoBuffer(_: *Self, buffer_id: BufferID.Enum) void {
        log_unimplemented("Video.selectVideoBuffer: {}", .{buffer_id});
    }

    /// Fill a specified video buffer with a single color.
    pub fn fillVideoBuffer(_: *Self, buffer_id: BufferID.Enum, color_id: ColorID.Trusted) void {
        log_unimplemented("Video.fillVideoBuffer: {} color:{}", .{ buffer_id, color_id });
    }

    /// Copy the contents of one video buffer into another at the specified vertical offset.
    pub fn copyVideoBuffer(_: *Self, source: BufferID.Enum, destination: BufferID.Enum, vertical_offset: Point.Coordinate) void {
        log_unimplemented("Video.copyVideoBuffer: source:{} destination:{} vertical_offset:{}", .{
            source,
            destination,
            vertical_offset,
        });
    }

    /// Render the contents of the specified buffer to the host screen after the specified delay.
    pub fn renderVideoBuffer(_: *Self, buffer_id: BufferID.Enum, delay: Video.Milliseconds) void {
        log_unimplemented("Video.renderVideoBuffer: {} delay:{}", .{
            buffer_id,
            delay,
        });
    }

    // -- Audio subsystem interface --

    /// Start playing a music track from a specified resource.
    /// Returns an error if the resource does not exist or could not be loaded.
    pub fn playMusic(_: *Self, resource_id: ResourceID.Raw, offset: Audio.Offset, delay: Audio.Delay) !void {
        log_unimplemented("Audio.playMusic: play #{X} at offset {} after delay {}", .{
            resource_id,
            offset,
            delay,
        });
    }

    /// Set on the current or subsequent music track.
    pub fn setMusicDelay(_: *Self, delay: Audio.Delay) void {
        log_unimplemented("Audio.setMusicDelay: set delay to {}", .{delay});
    }

    /// Stop playing any current music track.
    pub fn stopMusic(_: *Self) void {
        log_unimplemented("Audio.stopMusic: stop playing", .{});
    }

    /// Play a sound effect from the specified resource on the specified channel.
    /// Returns an error if the resource does not exist or could not be loaded.
    pub fn playSound(_: *Self, resource_id: ResourceID.Raw, channel: Channel.Trusted, volume: Audio.Volume, frequency: Audio.Frequency) !void {
        log_unimplemented("Audio.playSound: play #{X} on channel {} at volume {}, frequency {}", .{
            resource_id,
            channel,
            volume,
            frequency,
        });
    }

    /// Stop any sound effect playing on the specified channel.
    pub fn stopChannel(_: *Self, channel: Channel.Trusted) void {
        log_unimplemented("Audio.stopChannel: stop playing on channel {}", .{channel});
    }
};

/// A placeholder program to keep tests happy until we flesh out the VM enough
/// to load a real program during its initialization.
const empty_program = [0]u8{};

pub fn new() Instance {
    var machine = Instance{
        .threads = [_]Thread.Instance{.{}} ** thread_count,
        .registers = [_]Register.Signed{0} ** register_count,
        .stack = Stack.Instance{},
        .program = Program.new(&empty_program),
    };

    // Initialize the main thread to begin execution at the start of the current program
    machine.threads[ThreadID.main].execution_state = .{ .active = 0 };

    return machine;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "new creates new virtual machine with expected state" {
    const machine = new();

    for (machine.threads) |thread, id| {
        if (id == ThreadID.main) {
            try testing.expectEqual(.{ .active = 0 }, thread.execution_state);
        } else {
            try testing.expectEqual(.inactive, thread.execution_state);
        }
        try testing.expectEqual(.running, thread.suspend_state);
    }

    for (machine.registers) |register| {
        try testing.expectEqual(0, register);
    }
}
