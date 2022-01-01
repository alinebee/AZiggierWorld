const Machine = @import("../../machine/machine.zig");
const Video = @import("../../machine/video.zig");
const Audio = @import("../../machine/audio.zig");

const Point = @import("../../values/point.zig");
const GamePart = @import("../../values/game_part.zig");
const Channel = @import("../../values/channel.zig");
const ResourceID = @import("../../values/resource_id.zig");
const ColorID = @import("../../values/color_id.zig");
const PaletteID = @import("../../values/palette_id.zig");
const StringID = @import("../../values/string_id.zig");
const BufferID = @import("../../values/buffer_id.zig");
const PolygonScale = @import("../../values/polygon_scale.zig");

const zeroes = @import("std").mem.zeroes;

/// Returns a fake Machine.Instance that defers to the specified struct to implement its functions.
/// This allows testing of Machine function calls that would produce changes in state that are hard
/// to measure (e.g. drawing on screen or producing audio).
pub fn new(comptime Implementation: type) MockMachine(Implementation) {
    return MockMachine(Implementation){
        .registers = zeroes(Machine.Registers),
        .call_counts = zeroes(CallCounts),
    };
}

const CallCounts = struct {
    drawPolygon: usize,
    drawString: usize,
    selectPalette: usize,
    selectVideoBuffer: usize,
    fillVideoBuffer: usize,
    copyVideoBuffer: usize,
    renderVideoBuffer: usize,
    scheduleGamePart: usize,
    loadResource: usize,
    unloadAllResources: usize,
    playMusic: usize,
    setMusicDelay: usize,
    stopMusic: usize,
    playSound: usize,
    stopChannel: usize,
};

fn MockMachine(comptime Implementation: type) type {
    return struct {
        registers: Machine.Registers,

        call_counts: CallCounts,

        const Self = @This();

        pub fn drawPolygon(self: *Self, source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: PolygonScale.Raw) !void {
            self.call_counts.drawPolygon += 1;
            try Implementation.drawPolygon(source, address, point, scale);
        }

        pub fn drawString(self: *Self, string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
            self.call_counts.drawString += 1;
            try Implementation.drawString(string_id, color_id, point);
        }

        pub fn selectPalette(self: *Self, palette_id: PaletteID.Trusted) void {
            self.call_counts.selectPalette += 1;
            Implementation.selectPalette(palette_id);
        }

        pub fn selectVideoBuffer(self: *Self, buffer_id: BufferID.Enum) void {
            self.call_counts.selectVideoBuffer += 1;
            Implementation.selectVideoBuffer(buffer_id);
        }

        pub fn fillVideoBuffer(self: *Self, buffer_id: BufferID.Enum, color_id: ColorID.Trusted) void {
            self.call_counts.fillVideoBuffer += 1;
            Implementation.fillVideoBuffer(buffer_id, color_id);
        }

        pub fn copyVideoBuffer(self: *Self, source: BufferID.Enum, destination: BufferID.Enum, vertical_offset: Point.Coordinate) void {
            self.call_counts.copyVideoBuffer += 1;
            Implementation.copyVideoBuffer(source, destination, vertical_offset);
        }

        pub fn renderVideoBuffer(self: *Self, buffer_id: BufferID.Enum, delay: Video.Milliseconds) void {
            self.call_counts.renderVideoBuffer += 1;
            Implementation.renderVideoBuffer(buffer_id, delay);
        }

        pub fn scheduleGamePart(self: *Self, game_part: GamePart.Enum) void {
            self.call_counts.scheduleGamePart += 1;
            Implementation.scheduleGamePart(game_part);
        }

        pub fn loadResource(self: *Self, resource_id: ResourceID.Raw) !void {
            self.call_counts.loadResource += 1;
            try Implementation.loadResource(resource_id);
        }

        pub fn unloadAllResources(self: *Self) void {
            self.call_counts.unloadAllResources += 1;
            Implementation.unloadAllResources();
        }

        pub fn playMusic(self: *Self, resource_id: ResourceID.Raw, offset: Audio.Offset, delay: Audio.Delay) !void {
            self.call_counts.playMusic += 1;
            try Implementation.playMusic(resource_id, offset, delay);
        }

        pub fn setMusicDelay(self: *Self, delay: Audio.Delay) void {
            self.call_counts.setMusicDelay += 1;
            Implementation.setMusicDelay(delay);
        }

        pub fn stopMusic(self: *Self) void {
            self.call_counts.stopMusic += 1;
            Implementation.stopMusic();
        }

        pub fn playSound(self: *Self, resource_id: ResourceID.Raw, channel: Channel.Trusted, volume: Audio.Volume, frequency: Audio.Frequency) !void {
            self.call_counts.playSound += 1;
            try Implementation.playSound(resource_id, channel, volume, frequency);
        }

        pub fn stopChannel(self: *Self, channel: Channel.Trusted) void {
            self.call_counts.stopChannel += 1;
            Implementation.stopChannel(channel);
        }
    };
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "MockMachine calls drawPolygon correctly on stub implementation" {
    var mock = new(struct {
        fn drawPolygon(source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: PolygonScale.Raw) !void {
            try testing.expectEqual(.animations, source);
            try testing.expectEqual(0xBEEF, address);
            try testing.expectEqual(320, point.x);
            try testing.expectEqual(200, point.y);
            try testing.expectEqual(128, scale);
        }
    });

    try mock.drawPolygon(.animations, 0xBEEF, .{ .x = 320, .y = 200 }, 128);
    try testing.expectEqual(1, mock.call_counts.drawPolygon);
}

test "MockMachine calls drawString correctly on stub implementation" {
    var mock = new(struct {
        fn drawString(string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
            try testing.expectEqual(0xBEEF, string_id);
            try testing.expectEqual(2, color_id);
            try testing.expectEqual(320, point.x);
            try testing.expectEqual(200, point.y);
        }
    });

    try mock.drawString(0xBEEF, 2, .{ .x = 320, .y = 200 });
    try testing.expectEqual(1, mock.call_counts.drawString);
}

test "MockMachine calls selectPalette correctly on stub implementation" {
    var mock = new(struct {
        fn selectPalette(palette_id: PaletteID.Trusted) void {
            testing.expectEqual(16, palette_id) catch {
                unreachable;
            };
        }
    });

    mock.selectPalette(16);
    try testing.expectEqual(1, mock.call_counts.selectPalette);
}

test "MockMachine calls selectVideoBuffer correctly on stub implementation" {
    var mock = new(struct {
        fn selectVideoBuffer(buffer_id: BufferID.Enum) void {
            testing.expectEqual(.front_buffer, buffer_id) catch {
                unreachable;
            };
        }
    });

    mock.selectVideoBuffer(.front_buffer);
    try testing.expectEqual(1, mock.call_counts.selectVideoBuffer);
}

test "MockMachine calls fillVideoBuffer correctly on stub implementation" {
    var mock = new(struct {
        fn fillVideoBuffer(buffer_id: BufferID.Enum, color_id: ColorID.Trusted) void {
            testing.expectEqual(.front_buffer, buffer_id) catch {
                unreachable;
            };
            testing.expectEqual(15, color_id) catch {
                unreachable;
            };
        }
    });

    mock.fillVideoBuffer(.front_buffer, 15);
    try testing.expectEqual(1, mock.call_counts.fillVideoBuffer);
}

test "MockMachine calls copyVideoBuffer correctly on stub implementation" {
    var mock = new(struct {
        fn copyVideoBuffer(source: BufferID.Enum, destination: BufferID.Enum, vertical_offset: Point.Coordinate) void {
            testing.expectEqual(.{ .specific = 1 }, source) catch {
                unreachable;
            };
            testing.expectEqual(.back_buffer, destination) catch {
                unreachable;
            };
            testing.expectEqual(176, vertical_offset) catch {
                unreachable;
            };
        }
    });

    mock.copyVideoBuffer(.{ .specific = 1 }, .back_buffer, 176);
    try testing.expectEqual(1, mock.call_counts.copyVideoBuffer);
}

test "MockMachine calls renderVideoBuffer correctly on stub implementation" {
    var mock = new(struct {
        fn renderVideoBuffer(buffer_id: BufferID.Enum, delay: Video.Milliseconds) void {
            testing.expectEqual(.back_buffer, buffer_id) catch unreachable;
            testing.expectEqual(5, delay) catch unreachable;
        }
    });

    mock.renderVideoBuffer(.back_buffer, 5);
    try testing.expectEqual(1, mock.call_counts.renderVideoBuffer);
}

test "MockMachine calls scheduleGamePart correctly on stub implementation" {
    var mock = new(struct {
        fn scheduleGamePart(game_part: GamePart.Enum) void {
            testing.expectEqual(.copy_protection, game_part) catch unreachable;
        }
    });

    mock.scheduleGamePart(.copy_protection);
    try testing.expectEqual(1, mock.call_counts.scheduleGamePart);
}

test "MockMachine calls loadResource correctly on stub implementation" {
    var mock = new(struct {
        fn loadResource(resource_id: ResourceID.Raw) !void {
            try testing.expectEqual(0x8BAD, resource_id);
        }
    });

    try mock.loadResource(0x8BAD);
    try testing.expectEqual(1, mock.call_counts.loadResource);
}

test "MockMachine calls unloadAllResources correctly on stub implementation" {
    var mock = new(struct {
        fn unloadAllResources() void {}
    });

    mock.unloadAllResources();
    try testing.expectEqual(1, mock.call_counts.unloadAllResources);
}

test "MockMachine calls playMusic correctly on stub implementation" {
    var mock = new(struct {
        fn playMusic(resource_id: ResourceID.Raw, offset: Audio.Offset, delay: Audio.Delay) !void {
            try testing.expectEqual(0xBEEF, resource_id);
            try testing.expectEqual(128, offset);
            try testing.expectEqual(1234, delay);
        }
    });

    try mock.playMusic(0xBEEF, 128, 1234);
    try testing.expectEqual(1, mock.call_counts.playMusic);
}

test "MockMachine calls setMusicDelay correctly on stub implementation" {
    var mock = new(struct {
        fn setMusicDelay(delay: Audio.Delay) void {
            testing.expectEqual(1234, delay) catch {
                unreachable;
            };
        }
    });

    mock.setMusicDelay(1234);
    try testing.expectEqual(1, mock.call_counts.setMusicDelay);
}

test "MockMachine calls stopMusic correctly on stub implementation" {
    var mock = new(struct {
        fn stopMusic() void {}
    });

    mock.stopMusic();
    try testing.expectEqual(1, mock.call_counts.stopMusic);
}

test "MockMachine calls playSound correctly on stub implementation" {
    var mock = new(struct {
        fn playSound(resource_id: ResourceID.Raw, channel: Channel.Trusted, volume: Audio.Volume, frequency: Audio.Frequency) !void {
            try testing.expectEqual(0xBEEF, resource_id);
            try testing.expectEqual(2, channel);
            try testing.expectEqual(64, volume);
            try testing.expectEqual(128, frequency);
        }
    });

    try mock.playSound(0xBEEF, 2, 64, 128);
    try testing.expectEqual(1, mock.call_counts.playSound);
}

test "MockMachine calls stopChannel correctly on stub implementation" {
    var mock = new(struct {
        fn stopChannel(channel: Channel.Trusted) void {
            testing.expectEqual(2, channel) catch {
                unreachable;
            };
        }
    });

    mock.stopChannel(2);
    try testing.expectEqual(1, mock.call_counts.stopChannel);
}
