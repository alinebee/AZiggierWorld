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
const audio = anotherworld.audio;
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
    /// The audio data of the sound effect.
    data: []const audio.Sample,
    /// The offset within the audio data which the sound will loop back to once it has played through.
    /// If null, the sample will play through once and then stop.
    loop_start: ?usize,

    /// Parse a slice of resource data as a sound effect.
    /// Returns a sound resource, or an error if the data was malformed.
    /// The resource stores pointers into the slice, and is only valid for the lifetime of the slice.
    pub fn parse(data: []const u8) ParseError!SoundResource {
        if (data.len < DataLayout.intro) return error.TruncatedData;

        const intro_length_data = data[DataLayout.intro_length..DataLayout.loop_length];
        const loop_length_data = data[DataLayout.loop_length..DataLayout.unused];

        const intro_length_in_words = @as(usize, std.mem.readIntBig(u16, intro_length_data));
        const loop_length_in_words = @as(usize, std.mem.readIntBig(u16, loop_length_data));

        const intro_length_in_bytes = intro_length_in_words * 2;
        const loop_length_in_bytes = loop_length_in_words * 2;

        const audio_start = DataLayout.intro;
        const audio_end = audio_start + intro_length_in_bytes + loop_length_in_bytes;

        if (audio_start == audio_end) return error.SoundEmpty;
        if (data.len < audio_end) return error.TruncatedData;
        if (data.len > audio_end) {
            // At least one sound effect resource in the Another World DOS game files
            // is padded out to a longer data length than the sample actually uses.
            log.debug("Slice too long for expected data: {} actual vs {} expected", .{ data.len, audio_end });
        }

        const self = SoundResource{
            .data = data[audio_start..audio_end],
            .loop_start = if (loop_length_in_bytes > 0) intro_length_in_bytes else null,
        };

        return self;
    }

    /// Given a byte offset that may be beyond the end of the sample,
    /// returns the sample at that offset, looping the sound if necessary.
    /// Returns `null` if the specified offset is beyond the end of
    /// the sound data and the sound is not looped.
    pub fn sampleAt(self: SoundResource, offset: usize) ?audio.Sample {
        if (offset < self.data.len) {
            return self.data[offset];
        } else if (self.loop_start) |loop_start| {
            const loop_length = self.data.len - loop_start;
            const offset_within_loop = (offset - loop_start) % loop_length;
            const looped_offset = loop_start + offset_within_loop;
            return self.data[looped_offset];
        } else {
            return null;
        }
    }

    pub const ParseError = error{
        /// The audio data defined a 0-length sound.
        SoundEmpty,
        /// The slice provided to SoundResource.parse was too short to hold the header,
        /// or too short to hold the intro and loop section described in the header.
        TruncatedData,
    };
};

const Fixtures = struct {
    const intro_data = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05 };
    const loop_data = [_]u8{ 0x06, 0x07, 0x08, 0x09 };

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

    const empty = [_]u8{
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
    };
};

// -- Tests --

const testing = @import("utils").testing;

// - parse tests -

test "parse correctly parses sound data with no loop" {
    const fixture = &Fixtures.intro_only;
    const sound = try SoundResource.parse(fixture);
    try testing.expectEqual(fixture[8..14], sound.data);
    try testing.expectEqual(null, sound.loop_start);
}

test "parse correctly parses sound data with only loop" {
    const fixture = &Fixtures.loop_only;
    const sound = try SoundResource.parse(fixture);
    try testing.expectEqual(fixture[8..12], sound.data);
    try testing.expectEqual(0, sound.loop_start);
}

test "parse correctly parses sound data with intro and loop" {
    const fixture = &Fixtures.intro_with_loop;
    const sound = try SoundResource.parse(fixture);

    try testing.expectEqual(fixture[8..18], sound.data);
    try testing.expectEqual(6, sound.loop_start);
}

test "parse correctly parses data that is longer than necessary" {
    const padded_fixture = &(Fixtures.intro_with_loop ++ [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04 });
    const sound = try SoundResource.parse(padded_fixture);
    try testing.expectEqual(padded_fixture[8..18], sound.data);
}

test "parse returns error.TruncatedData for data too short to fit header" {
    const truncated_fixture = Fixtures.intro_with_loop[0..4];
    try testing.expectError(error.TruncatedData, SoundResource.parse(truncated_fixture));
}

test "parse returns error.SoundEmpty for sound effect that defines 0 length" {
    try testing.expectError(error.SoundEmpty, SoundResource.parse(&Fixtures.empty));
}

test "parse returns error.TruncatedData for data too short to fit intro length for intro-only sound effect" {
    const truncated_fixture = Fixtures.intro_only[0 .. Fixtures.intro_only.len - 1];
    try testing.expectError(error.TruncatedData, SoundResource.parse(truncated_fixture));
}

test "parse returns error.TruncatedData for data too short to fit loop length for looped sound effect" {
    const truncated_fixture = Fixtures.loop_only[0 .. Fixtures.loop_only.len - 1];
    try testing.expectError(error.TruncatedData, SoundResource.parse(truncated_fixture));
}

test "parse returns error.TruncatedData for data too short to fit loop length for sound effect with intro and loop" {
    const truncated_fixture = Fixtures.intro_with_loop[0 .. Fixtures.intro_with_loop.len - 1];
    try testing.expectError(error.TruncatedData, SoundResource.parse(truncated_fixture));
}

// - sampleAt tests -

test "sampleAt returns data for in-range offsets and null for out-of-range offsets when sound is unlooped" {
    const sound = SoundResource{
        .data = &[_]u8{ 0, 2, 4, 6, 8 },
        .loop_start = null,
    };

    try testing.expectEqual(0, sound.sampleAt(0));
    try testing.expectEqual(2, sound.sampleAt(1));
    try testing.expectEqual(4, sound.sampleAt(2));
    try testing.expectEqual(6, sound.sampleAt(3));
    try testing.expectEqual(8, sound.sampleAt(4));
    try testing.expectEqual(null, sound.sampleAt(5));
}

test "sampleAt returns data for all offsets when sound is looped" {
    const sound = SoundResource{
        .data = &[_]u8{ 0, 2, 4, 6, 8 },
        .loop_start = 3,
    };

    try testing.expectEqual(0, sound.sampleAt(0));
    try testing.expectEqual(2, sound.sampleAt(1));
    try testing.expectEqual(4, sound.sampleAt(2));
    try testing.expectEqual(6, sound.sampleAt(3));
    try testing.expectEqual(8, sound.sampleAt(4));
    try testing.expectEqual(6, sound.sampleAt(5));
    try testing.expectEqual(8, sound.sampleAt(6));
    try testing.expectEqual(6, sound.sampleAt(7));
    try testing.expectEqual(8, sound.sampleAt(8));
}
