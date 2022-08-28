const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const resources = anotherworld.resources;
const audio = anotherworld.audio;

// Instruments with this resource ID will not be played
const no_instrument_marker = 0;

pub const Instrument = struct {
    resource_id: resources.ResourceID,
    volume: audio.Volume,

    pub fn parse(data: Raw) ?Instrument {
        const raw_resource_id = std.mem.readIntBig(u16, data[0..2]);

        if (raw_resource_id != no_instrument_marker) {
            // TODO: return a userspace error when volume is out of range (0..64)
            const raw_volume = @intCast(audio.Volume, std.mem.readIntBig(u16, data[2..4]));
            return Instrument{
                .resource_id = resources.ResourceID.cast(raw_resource_id),
                .volume = raw_volume,
            };
        } else {
            return null;
        }
    }

    pub const Raw = [4]u8;
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(Instrument);
}
