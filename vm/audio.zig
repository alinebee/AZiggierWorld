//! Extends Machine.Instance with methods for sound and music playback.

const Machine = @import("machine.zig");
const ResourceID = @import("types/resource_id.zig");
const Channel = @import("types/channel.zig");

pub const Delay = u16;
pub const Offset = u8;

pub const Volume = u8;
pub const Frequency = u8;

const log_unimplemented = @import("../utils/logging.zig").log_unimplemented;

/// Start playing a music track from a specified resource.
/// Returns an error if the resource does not exist or could not be loaded.
pub fn playMusic(self: *Machine.Instance, resource_id: ResourceID.Raw, offset: Offset, delay: Delay) !void {
    log_unimplemented("Audio.playMusic: play #{X} at offset {} after delay {}", .{
        resource_id,
        offset,
        delay,
    });
}

/// Set on the current or subsequent music track.
pub fn setMusicDelay(self: *Machine.Instance, delay: Delay) void {
    log_unimplemented("Audio.setMusicDelay: set delay to {}", .{delay});
}

/// Stop playing any current music track.
pub fn stopMusic(self: *Machine.Instance) void {
    log_unimplemented("Audio.stopMusic: stop playing", .{});
}

/// Play a sound effect from the specified resource on the specified channel.
/// Returns an error if the resource does not exist or could not be loaded.
pub fn playSound(self: *Machine.Instance, resource_id: ResourceID.Raw, channel: Channel.Enum, volume: Volume, frequency: Frequency) !void {
    log_unimplemented("Audio.playSound: play #{X} on channel {} at volume {}, frequency {}", .{
        resource_id,
        @tagName(channel),
        volume,
        frequency,
    });
}

/// Stop any sound effect playing on the specified channel.
pub fn stopChannel(self: *Machine.Instance, channel: Channel.Enum) void {
    log_unimplemented("Audio.stopChannel: stop playing on channel {}", .{@tagName(channel)});
}
