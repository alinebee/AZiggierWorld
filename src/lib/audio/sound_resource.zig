//! Sound effect resources have the following big-endian data layout:
//! (Byte offset, type, purpose, description)
//! ------HEADER------
//! 0..2    u16     intro length    Length in 16-bit words of intro section.
//! 2..4    u16     loop length     Length in 16-bit words of loop section.
//!                                 0 if sound does not loop.
//! 4..8  unused
//! ------DATA------
//! 8..loop_section_start       u8[]    intro data  played through once, then switches to loop
//! loop_section_start..end     u8[]    loop data   played continuously, restarting from start of loop data

const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const log = anotherworld.log;

/// Data offsets within a sound effect resource.
const DataLayout = struct {
    const intro_length = 0x00;
    const loop_length = 0x02;
    const unused = 0x04;
    const intro = 0x08;
};

/// Parses an Another World sound effect resource into a structure that can be played back on a mixer.
pub const SoundResource = struct {
    /// The non-repeated intro section of the sound effect.
    /// Once this plays through, the sample will move on to the looped section.
    /// Null if the sound effect loops without an intro.
    intro: ?[]const u8,
    /// The looped section of the sound effect.
    /// Null if the sound effect does not loop.
    loop: ?[]const u8,

    /// Parse a slice of resource data as a sound effect.
    /// Returns a sound resource, or an error if the data was malformed.
    /// The resource stores pointers into the slice, and is only valid for the lifetime of the slice.
    pub fn parse(data: []const u8) ParseError!SoundResource {
        if (data.len < DataLayout.intro) return error.TruncatedData;

        const intro_length_data = data[DataLayout.intro_length..DataLayout.loop_length];
        const loop_length_data = data[DataLayout.loop_length..DataLayout.unused];

        const intro_length_in_words = @as(usize, std.mem.readIntBig(u16, intro_length_data));
        const loop_length_in_words = @as(usize, std.mem.readIntBig(u16, loop_length_data));

        const intro_start = DataLayout.intro;
        const intro_end = intro_start + (intro_length_in_words * 2);

        const loop_start = intro_end;
        const loop_end = loop_start + (loop_length_in_words * 2);

        if (data.len < loop_end) return error.TruncatedData;
        if (data.len > loop_end) {
            // At least one sound effect resource in the Another World DOS game files
            // is padded out to a longer data length than the sample actually uses.
            log.debug("Slice too long for expected data: {} actual vs {} expected", .{ data.len, loop_end });
        }

        const self = SoundResource{
            .intro = if (intro_end > intro_start) data[intro_start..intro_end] else null,
            .loop = if (loop_end > loop_start) data[loop_start..loop_end] else null,
        };

        if (self.intro == null and self.loop == null) {
            log.debug("Empty sound effect", .{});
        }

        return self;
    }

    pub const ParseError = error{
        // The slice provided to SoundResource.parse was too short to hold the header,
        // or too short to hold the intro and loop section described in the header.
        TruncatedData,
    };
};

const testing = @import("utils").testing;

const Fixtures = struct {
    const intro_data = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06 };
    const loop_data = [_]u8{ 0x01, 0x02, 0x03, 0x04 };

    const intro_only = [_]u8{
        0x00, 0x03, // Intro data is 3 words (6 bytes) long
        0x00, 0x00, // Loop data is 0 words (0 bytes) long
        // Rest of header is unused
        0x00, 0x00,
        0x00, 0x00,
    } ++ intro_data;

    const loop_only = [_]u8{
        0x00, 0x00, // Intro data is 0 words (0 bytes) long
        0x00, 0x02, // Loop data is 2 words (4 bytes) long
        // Rest of header is unused
        0x00, 0x00,
        0x00, 0x00,
    } ++ loop_data;

    const intro_with_loop = [_]u8{
        0x00, 0x03, // Intro data is 3 words (6 bytes) long
        0x00, 0x02, // Loop data is 2 words (4 bytes) long
        // Rest of header is unused
        0x00, 0x00,
        0x00, 0x00,
    } ++ intro_data ++ loop_data;
};

test "init parses sound data with only intro" {
    const fixture = &Fixtures.intro_only;
    const sound = try SoundResource.parse(fixture);
    try testing.expectEqual(fixture[8..14], sound.intro);
    try testing.expectEqual(null, sound.loop);
}

test "init parses sound data with only loop" {
    const fixture = &Fixtures.loop_only;
    const sound = try SoundResource.parse(fixture);
    try testing.expectEqual(null, sound.intro);
    try testing.expectEqual(fixture[8..12], sound.loop);
}

test "init parses sound data with intro and loop" {
    const fixture = &Fixtures.intro_with_loop;
    const sound = try SoundResource.parse(fixture);
    try testing.expectEqual(fixture[8..14], sound.intro);
    try testing.expectEqual(fixture[14..], sound.loop);
}

test "init parsed data that is longer than necessary" {
    const padded_fixture = &(Fixtures.intro_with_loop ++ [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04 });
    const sound = try SoundResource.parse(padded_fixture);
    try testing.expectEqual(padded_fixture[8..14], sound.intro);
    try testing.expectEqual(padded_fixture[14..18], sound.loop);
}

test "init returns error.TruncatedData for data too short to fit header" {
    const truncated_fixture = Fixtures.intro_with_loop[0..4];
    try testing.expectError(error.TruncatedData, SoundResource.parse(truncated_fixture));
}

test "init returns error.TruncatedData for data too short to fit intro length for intro-only sound effect" {
    const truncated_fixture = Fixtures.intro_only[0 .. Fixtures.intro_only.len - 1];
    try testing.expectError(error.TruncatedData, SoundResource.parse(truncated_fixture));
}

test "init returns error.TruncatedData for data too short to fit loop length for looped sound effect" {
    const truncated_fixture = Fixtures.loop_only[0 .. Fixtures.loop_only.len - 1];
    try testing.expectError(error.TruncatedData, SoundResource.parse(truncated_fixture));
}

test "init returns error.TruncatedData for data too short to fit loop length for sound effect with intro and loop" {
    const truncated_fixture = Fixtures.intro_with_loop[0 .. Fixtures.intro_with_loop.len - 1];
    try testing.expectError(error.TruncatedData, SoundResource.parse(truncated_fixture));
}
