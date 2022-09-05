const anotherworld = @import("../../anotherworld.zig");
const rendering = anotherworld.rendering;
const resources = anotherworld.resources;
const text = anotherworld.text;
const audio = anotherworld.audio;
const vm = anotherworld.vm;

const Registers = @import("../registers.zig").Registers;

const zeroes = @import("std").mem.zeroes;

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
    setMusicTempo: usize,
    stopMusic: usize,
    playSound: usize,
    stopChannel: usize,
};

pub fn mockMachine(comptime Implementation: type) MockMachine(Implementation) {
    return MockMachine(Implementation){};
}

pub fn MockMachine(comptime Implementation: type) type {
    return struct {
        registers: Registers = .{},

        call_counts: CallCounts = zeroes(CallCounts),

        const Self = @This();

        pub fn drawPolygon(self: *Self, source: vm.PolygonSource, address: rendering.PolygonResource.Address, point: rendering.Point, scale: rendering.PolygonScale) !void {
            self.call_counts.drawPolygon += 1;
            try Implementation.drawPolygon(source, address, point, scale);
        }

        pub fn drawString(self: *Self, string_id: text.StringID, color_id: rendering.ColorID, point: rendering.Point) !void {
            self.call_counts.drawString += 1;
            try Implementation.drawString(string_id, color_id, point);
        }

        pub fn selectPalette(self: *Self, palette_id: rendering.PaletteID) !void {
            self.call_counts.selectPalette += 1;
            try Implementation.selectPalette(palette_id);
        }

        pub fn selectVideoBuffer(self: *Self, buffer_id: vm.BufferID) void {
            self.call_counts.selectVideoBuffer += 1;
            Implementation.selectVideoBuffer(buffer_id);
        }

        pub fn fillVideoBuffer(self: *Self, buffer_id: vm.BufferID, color_id: rendering.ColorID) void {
            self.call_counts.fillVideoBuffer += 1;
            Implementation.fillVideoBuffer(buffer_id, color_id);
        }

        pub fn copyVideoBuffer(self: *Self, source: vm.BufferID, destination: vm.BufferID, vertical_offset: rendering.Point.Coordinate) void {
            self.call_counts.copyVideoBuffer += 1;
            Implementation.copyVideoBuffer(source, destination, vertical_offset);
        }

        pub fn renderVideoBuffer(self: *Self, buffer_id: vm.BufferID, delay_in_frames: vm.FrameCount) void {
            self.call_counts.renderVideoBuffer += 1;
            Implementation.renderVideoBuffer(buffer_id, delay_in_frames);
        }

        pub fn scheduleGamePart(self: *Self, game_part: vm.GamePart) void {
            self.call_counts.scheduleGamePart += 1;
            Implementation.scheduleGamePart(game_part);
        }

        pub fn loadResource(self: *Self, resource_id: resources.ResourceID) !void {
            self.call_counts.loadResource += 1;
            try Implementation.loadResource(resource_id);
        }

        pub fn unloadAllResources(self: *Self) void {
            self.call_counts.unloadAllResources += 1;
            Implementation.unloadAllResources();
        }

        pub fn playMusic(self: *Self, resource_id: resources.ResourceID, offset: audio.Offset, tempo: ?audio.Tempo) !void {
            self.call_counts.playMusic += 1;
            try Implementation.playMusic(resource_id, offset, tempo);
        }

        pub fn setMusicTempo(self: *Self, tempo: audio.Tempo) !void {
            self.call_counts.setMusicTempo += 1;
            try Implementation.setMusicTempo(tempo);
        }

        pub fn stopMusic(self: *Self) void {
            self.call_counts.stopMusic += 1;
            Implementation.stopMusic();
        }

        pub fn playSound(self: *Self, resource_id: resources.ResourceID, channel_id: audio.ChannelID, volume: audio.Volume, frequency_id: audio.FrequencyID) !void {
            self.call_counts.playSound += 1;
            try Implementation.playSound(resource_id, channel_id, volume, frequency_id);
        }

        pub fn stopChannel(self: *Self, channel_id: audio.ChannelID) void {
            self.call_counts.stopChannel += 1;
            Implementation.stopChannel(channel_id);
        }
    };
}

// -- Tests --

const testing = @import("utils").testing;

test "MockMachine calls drawPolygon correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn drawPolygon(source: vm.PolygonSource, address: rendering.PolygonResource.Address, point: rendering.Point, scale: rendering.PolygonScale) !void {
            try testing.expectEqual(.animations, source);
            try testing.expectEqual(0xBEEF, address);
            try testing.expectEqual(320, point.x);
            try testing.expectEqual(200, point.y);
            try testing.expectEqual(.double, scale);
        }
    });

    try mock.drawPolygon(.animations, 0xBEEF, .{ .x = 320, .y = 200 }, .double);
    try testing.expectEqual(1, mock.call_counts.drawPolygon);
}

test "MockMachine calls drawString correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn drawString(string_id: text.StringID, color_id: rendering.ColorID, point: rendering.Point) !void {
            try testing.expectEqual(text.StringID.cast(0xBEEF), string_id);
            try testing.expectEqual(rendering.ColorID.cast(2), color_id);
            try testing.expectEqual(320, point.x);
            try testing.expectEqual(200, point.y);
        }
    });

    try mock.drawString(text.StringID.cast(0xBEEF), rendering.ColorID.cast(2), .{ .x = 320, .y = 200 });
    try testing.expectEqual(1, mock.call_counts.drawString);
}

test "MockMachine calls selectPalette correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn selectPalette(palette_id: rendering.PaletteID) !void {
            testing.expectEqual(rendering.PaletteID.cast(16), palette_id) catch {
                unreachable;
            };
        }
    });

    try mock.selectPalette(rendering.PaletteID.cast(16));
    try testing.expectEqual(1, mock.call_counts.selectPalette);
}

test "MockMachine calls selectVideoBuffer correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn selectVideoBuffer(buffer_id: vm.BufferID) void {
            testing.expectEqual(.front_buffer, buffer_id) catch {
                unreachable;
            };
        }
    });

    mock.selectVideoBuffer(.front_buffer);
    try testing.expectEqual(1, mock.call_counts.selectVideoBuffer);
}

test "MockMachine calls fillVideoBuffer correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn fillVideoBuffer(buffer_id: vm.BufferID, color_id: rendering.ColorID) void {
            testing.expectEqual(.front_buffer, buffer_id) catch {
                unreachable;
            };
            testing.expectEqual(rendering.ColorID.cast(15), color_id) catch {
                unreachable;
            };
        }
    });

    mock.fillVideoBuffer(.front_buffer, rendering.ColorID.cast(15));
    try testing.expectEqual(1, mock.call_counts.fillVideoBuffer);
}

test "MockMachine calls copyVideoBuffer correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn copyVideoBuffer(source: vm.BufferID, destination: vm.BufferID, vertical_offset: rendering.Point.Coordinate) void {
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
    var mock = mockMachine(struct {
        fn renderVideoBuffer(buffer_id: vm.BufferID, delay_in_frames: vm.FrameCount) void {
            testing.expectEqual(.back_buffer, buffer_id) catch unreachable;
            testing.expectEqual(5, delay_in_frames) catch unreachable;
        }
    });

    mock.renderVideoBuffer(.back_buffer, 5);
    try testing.expectEqual(1, mock.call_counts.renderVideoBuffer);
}

test "MockMachine calls scheduleGamePart correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn scheduleGamePart(game_part: vm.GamePart) void {
            testing.expectEqual(.copy_protection, game_part) catch unreachable;
        }
    });

    mock.scheduleGamePart(.copy_protection);
    try testing.expectEqual(1, mock.call_counts.scheduleGamePart);
}

test "MockMachine calls loadResource correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn loadResource(resource_id: resources.ResourceID) !void {
            try testing.expectEqual(resources.ResourceID.cast(0x8BAD), resource_id);
        }
    });

    try mock.loadResource(resources.ResourceID.cast(0x8BAD));
    try testing.expectEqual(1, mock.call_counts.loadResource);
}

test "MockMachine calls unloadAllResources correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn unloadAllResources() void {}
    });

    mock.unloadAllResources();
    try testing.expectEqual(1, mock.call_counts.unloadAllResources);
}

test "MockMachine calls playMusic correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn playMusic(resource_id: resources.ResourceID, offset: audio.Offset, tempo: ?audio.Tempo) !void {
            try testing.expectEqual(resources.ResourceID.cast(0xBEEF), resource_id);
            try testing.expectEqual(128, offset);
            try testing.expectEqual(1234, tempo);
        }
    });

    try mock.playMusic(resources.ResourceID.cast(0xBEEF), 128, 1234);
    try testing.expectEqual(1, mock.call_counts.playMusic);
}

test "MockMachine calls setMusicTempo correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn setMusicTempo(tempo: audio.Tempo) !void {
            testing.expectEqual(1234, tempo) catch {
                unreachable;
            };
        }
    });

    try mock.setMusicTempo(1234);
    try testing.expectEqual(1, mock.call_counts.setMusicTempo);
}

test "MockMachine calls stopMusic correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn stopMusic() void {}
    });

    mock.stopMusic();
    try testing.expectEqual(1, mock.call_counts.stopMusic);
}

test "MockMachine calls playSound correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn playSound(resource_id: resources.ResourceID, channel_id: audio.ChannelID, volume: audio.Volume, frequency_id: audio.FrequencyID) !void {
            try testing.expectEqual(resources.ResourceID.cast(0xBEEF), resource_id);
            try testing.expectEqual(audio.ChannelID.cast(2), channel_id);
            try testing.expectEqual(64, volume);
            try testing.expectEqual(try audio.FrequencyID.parse(39), frequency_id);
        }
    });

    try mock.playSound(resources.ResourceID.cast(0xBEEF), audio.ChannelID.cast(2), 64, try audio.FrequencyID.parse(39));
    try testing.expectEqual(1, mock.call_counts.playSound);
}

test "MockMachine calls stopChannel correctly on stub implementation" {
    var mock = mockMachine(struct {
        fn stopChannel(channel_id: audio.ChannelID) void {
            testing.expectEqual(audio.ChannelID.cast(2), channel_id) catch {
                unreachable;
            };
        }
    });

    mock.stopChannel(audio.ChannelID.cast(2));
    try testing.expectEqual(1, mock.call_counts.stopChannel);
}
