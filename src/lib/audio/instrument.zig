const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const resources = anotherworld.resources;
const audio = anotherworld.audio;

// Instruments with this resource ID will not be played.
const no_instrument_marker = 0;

/// An instrument in a music track. Instruments map instruments IDs in a music track
/// to sound resources in Another World's game data.
pub const Instrument = struct {
    /// The ID of the resource to load for this instrument.
    resource_id: resources.ResourceID,
    /// The default volume at which to play this instrument.
    /// This can be adjusted up or down by channel events.
    volume: audio.Volume,

    /// Parse a raw 4-byte code from a music resource header into an instrument definition.
    /// Returns an instrument or null if the instrument was blank.
    /// Returns an error if the instrument could not be parsed.
    pub fn parse(data: Raw) ?Instrument {
        const raw_resource_id = std.mem.readIntBig(resources.ResourceID.Raw, data[0..2]);

        if (raw_resource_id != no_instrument_marker) {
            const raw_volume = std.mem.readIntBig(RawVolume, data[2..4]);
            return Instrument{
                .resource_id = resources.ResourceID.cast(raw_resource_id),
                .volume = audio.Volume.cast(raw_volume),
            };
        } else {
            return null;
        }
    }

    pub const Raw = [4]u8;

    /// Unlike bytecode data, instrument data defines volumes as 16-bit unsigned integers.
    const RawVolume = u16;

    pub const Fixtures = struct {
        /// resource ID 0x1234, volume 63
        pub const instrument = [4]u8{ 0x12, 0x34, 0x00, 0x3F };
        pub const no_instrument = [4]u8{ 0x00, 0x00, 0x00, 0x00 };
        /// resource ID 0x1234, volume 655035
        pub const out_of_range_volume = [4]u8{ 0x12, 0x34, 0xFF, 0xFF };
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
        .volume = audio.Volume.cast(63),
    };
    try testing.expectEqual(expected, Instrument.parse(Instrument.Fixtures.instrument));
}

test "parse returns null for blank instrument definition" {
    try testing.expectEqual(null, Instrument.parse(Instrument.Fixtures.no_instrument));
}

test "parse clamps out-of-range volumes" {
    const expected = Instrument{
        .resource_id = resources.ResourceID.cast(0x1234),
        .volume = audio.Volume.cast(63),
    };
    try testing.expectEqual(expected, Instrument.parse(Instrument.Fixtures.out_of_range_volume));
}
