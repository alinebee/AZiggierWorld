const Machine = @import("../../machine/machine.zig");
const Video = @import("../../machine/video.zig");
const Audio = @import("../../machine/audio.zig");

const Point = @import("../../values/point.zig");
const GamePart = @import("../../values/game_part.zig");
const Channel = @import("../../values/channel.zig");
const ResourceID = @import("../../values/resource_id.zig");
const ColorID = @import("../../values/color_id.zig");
const StringID = @import("../../values/string_id.zig");

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
    startGamePart: usize,
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

        pub fn drawPolygon(self: *Self, source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: Video.PolygonScale) !void {
            self.call_counts.drawPolygon += 1;
            try Implementation.drawPolygon(source, address, point, scale);
        }

        pub fn drawString(self: *Self, string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
            self.call_counts.drawString += 1;
            try Implementation.drawString(string_id, color_id, point);
        }

        pub fn startGamePart(self: *Self, game_part: GamePart.Enum) !void {
            self.call_counts.startGamePart += 1;
            try Implementation.startGamePart(game_part);
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
        fn drawPolygon(source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: Video.PolygonScale) !void {
            testing.expectEqual(.animations, source);
            testing.expectEqual(0xBEEF, address);
            testing.expectEqual(320, point.x);
            testing.expectEqual(200, point.y);
            testing.expectEqual(128, scale);
        }
    });

    try mock.drawPolygon(.animations, 0xBEEF, .{ .x = 320, .y = 200 }, 128);
    testing.expectEqual(1, mock.call_counts.drawPolygon);
}

test "MockMachine calls drawString correctly on stub implementation" {
    var mock = new(struct {
        fn drawString(string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
            testing.expectEqual(0xBEEF, string_id);
            testing.expectEqual(2, color_id);
            testing.expectEqual(320, point.x);
            testing.expectEqual(200, point.y);
        }
    });

    try mock.drawString(0xBEEF, 2, .{ .x = 320, .y = 200 });
    testing.expectEqual(1, mock.call_counts.drawString);
}

test "MockMachine calls startGamePart correctly on stub implementation" {
    var mock = new(struct {
        fn startGamePart(game_part: GamePart.Enum) !void {
            testing.expectEqual(.copy_protection, game_part);
        }
    });

    try mock.startGamePart(.copy_protection);
    testing.expectEqual(1, mock.call_counts.startGamePart);
}

test "MockMachine calls loadResource correctly on stub implementation" {
    var mock = new(struct {
        fn loadResource(resource_id: ResourceID.Raw) !void {
            testing.expectEqual(0x8BAD, resource_id);
        }
    });

    try mock.loadResource(0x8BAD);
    testing.expectEqual(1, mock.call_counts.loadResource);
}

test "MockMachine calls unloadAllResources correctly on stub implementation" {
    var mock = new(struct {
        fn unloadAllResources() void {}
    });

    mock.unloadAllResources();
    testing.expectEqual(1, mock.call_counts.unloadAllResources);
}

test "MockMachine calls playMusic correctly on stub implementation" {
    var mock = new(struct {
        fn playMusic(resource_id: ResourceID.Raw, offset: Audio.Offset, delay: Audio.Delay) !void {
            testing.expectEqual(0xBEEF, resource_id);
            testing.expectEqual(128, offset);
            testing.expectEqual(1234, delay);
        }
    });

    try mock.playMusic(0xBEEF, 128, 1234);
    testing.expectEqual(1, mock.call_counts.playMusic);
}

test "MockMachine calls setMusicDelay correctly on stub implementation" {
    var mock = new(struct {
        fn setMusicDelay(delay: Audio.Delay) void {
            testing.expectEqual(1234, delay);
        }
    });

    mock.setMusicDelay(1234);
    testing.expectEqual(1, mock.call_counts.setMusicDelay);
}

test "MockMachine calls stopMusic correctly on stub implementation" {
    var mock = new(struct {
        fn stopMusic() void {}
    });

    mock.stopMusic();
    testing.expectEqual(1, mock.call_counts.stopMusic);
}

test "MockMachine calls playSound correctly on stub implementation" {
    var mock = new(struct {
        fn playSound(resource_id: ResourceID.Raw, channel: Channel.Trusted, volume: Audio.Volume, frequency: Audio.Frequency) !void {
            testing.expectEqual(0xBEEF, resource_id);
            testing.expectEqual(2, channel);
            testing.expectEqual(64, volume);
            testing.expectEqual(128, frequency);
        }
    });

    try mock.playSound(0xBEEF, 2, 64, 128);
    testing.expectEqual(1, mock.call_counts.playSound);
}

test "MockMachine calls stopChannel correctly on stub implementation" {
    var mock = new(struct {
        fn stopChannel(channel: Channel.Trusted) void {
            testing.expectEqual(2, channel);
        }
    });

    mock.stopChannel(2);
    testing.expectEqual(1, mock.call_counts.stopChannel);
}
