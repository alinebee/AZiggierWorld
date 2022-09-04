const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const resources = anotherworld.resources;
const audio = anotherworld.audio;

// Instruments with this resource ID will not be played
const no_instrument_marker = 0;

pub const Instrument = struct {
    resource_id: resources.ResourceID,
    volume: audio.Volume,

    /// Parse a raw 4-byte code from a music resource header into an instrument definition.
    /// Returns an instrument, or null if the instrument was blank.
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

    pub const Fixtures = struct {
        pub const instrument = [4]u8{ 0x12, 0x34, 0x00, 0x3F };
        pub const no_instrument = [4]u8{ 0x00, 0x00, 0x00, 0x00 };
    };
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
    try testing.expectEqual(expected, Instrument.parse(Instrument.Fixtures.instrument));
}

test "parse returns null for blank instrument definition" {
    try testing.expectEqual(null, Instrument.parse(Instrument.Fixtures.no_instrument));
}
