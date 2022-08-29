const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const resources = anotherworld.resources;
const audio = anotherworld.audio;

// Instruments with this resource ID will not be played
const no_instrument_marker = 0;

pub const Instrument = struct {
    resource_id: resources.ResourceID,
    volume: audio.Volume.Trusted,

    pub fn parse(data: Raw) ParseError!?Instrument {
        const raw_resource_id = std.mem.readIntBig(u16, data[0..2]);
        const raw_volume = std.mem.readIntBig(u16, data[2..4]);

        if (raw_resource_id != no_instrument_marker) {
            return Instrument{
                .resource_id = resources.ResourceID.cast(raw_resource_id),
                .volume = try audio.Volume.parse(raw_volume),
            };
        } else {
            return null;
        }
    }

    pub const Raw = [4]u8;

    pub const ParseError = audio.Volume.ParseError;
};

const Fixtures = struct {
    const instrument = [4]u8{ 0x12, 0x34, 0x00, 0x3F };
    const no_instrument = [4]u8{ 0x00, 0x00, 0x00, 0x00 };
    const invalid_volume = [4]u8{ 0x12, 0x34, 0x00, 0x40 };
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(Instrument);
}

test "parse returns correct raw instrument definition" {
    const expected = Instrument{
        .resource_id = resources.ResourceID.cast(0x1234),
        .volume = 63,
    };
    try testing.expectEqual(expected, try Instrument.parse(Fixtures.instrument));
}

test "parse returns null for blank instrument definition" {
    try testing.expectEqual(null, try Instrument.parse(Fixtures.no_instrument));
}

test "parse returns error.VolumeOutOfRange for instrument definition with invalid volume" {
    try testing.expectError(error.VolumeOutOfRange, Instrument.parse(Fixtures.invalid_volume));
}
