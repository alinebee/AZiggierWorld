//! Sound effect resources have the following big-endian data layout:
//! (Byte offset, type, purpose, description)
//! ------HEADER------
//! 0..2    u16     intro length    Length in 16-bit words of intro section.
//! 2..4    u16     loop length     Length in 16-bit words of loop section.
//!                                 0 if sound does not loop.
//! 4..8  unused
//! ------DATA------
//! 8..loop_section_start       i8[]    intro data  played through once, then switches to loop
//! loop_section_start..end     i8[]    loop data   played continuously, restarting from start of loop data
//!

// TODO: The reference implementation modified sound data in place to zero out the first 4 bytes
// of all audio samples that were loaded as music track instruments. This may mean those samples
// contained junk data; or it may have been cargo-culted from music tracker implementations,
// which apparently would silence a given channel by playing an empty sample that looped indefinitely
// over its starting bytes. Either way, we should reimplement this behaviour if it makes any difference
// to how the music actually sounds.
// Reference:
// https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/sfxplayer.cpp#L88

const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const audio = anotherworld.audio;
const log = anotherworld.log;

const interpolation = @import("interpolation.zig");

/// Parses an Another World sound effect data into a resource that can be played back on a mixer.
pub const SoundResource = struct {
    /// The unlooped intro portion of the sound effect.
    /// If 0-length, the loop portion of the sound effect will be played immediately.
    intro: []const u8,
    /// The portion of the sound effect that is looped indefinitely.
    /// If 0-length, the intro portion of the sound effect will be played once and then stop.
    loop: []const u8,

    /// Parse a slice of resource data as a sound effect.
    /// Returns a sound resource, or an error if the data was malformed.
    /// The resource stores pointers into the slice, and is only valid for the lifetime of the slice.
    pub fn parse(data: []const u8) ParseError!SoundResource {
        if (data.len < DataLayout.intro) return error.TruncatedData;

        const intro_length_data = data[DataLayout.intro_length..DataLayout.loop_length];
        const loop_length_data = data[DataLayout.loop_length..DataLayout.unused];

        const intro_length_in_words = @as(usize, std.mem.readIntBig(u16, intro_length_data));
        const loop_length_in_words = @as(usize, std.mem.readIntBig(u16, loop_length_data));

        // Uncomment to emulate a bug from reference implementation which looped a sound effect
        // to a point too early in the sample:
        // ----
        //   var intro_length_in_bytes = intro_length_in_words * 2;
        //   var loop_length_in_bytes = loop_length_in_words * 2;
        //   if (loop_length_in_bytes > 0) {
        //       const buggy_intro_length_in_bytes = intro_length_in_bytes >> 8;
        //       const bug_difference = intro_length_in_bytes - buggy_intro_length_in_bytes;
        //       intro_length_in_bytes -= bug_difference;
        //       loop_length_in_bytes += bug_difference;
        //   }
        // ----
        // See: https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/mixer.cpp#L119
        // (It failed to account for chunkPos being left-shifted by 8 bits when setting chunkPos to loopPos to rewind.)

        const intro_length_in_bytes = intro_length_in_words * 2;
        const loop_length_in_bytes = loop_length_in_words * 2;

        const intro_start = DataLayout.intro;
        const intro_end = intro_start + intro_length_in_bytes;
        const loop_start = intro_end;
        const loop_end = loop_start + loop_length_in_bytes;

        if (data.len < loop_end) return error.TruncatedData;
        if (data.len > loop_end) {
            // At least one sound effect resource in the Another World DOS game files
            // is padded out to a longer data length than the sample actually uses.
            log.debug("Slice too long for expected data: {} actual vs {} expected", .{ data.len, loop_end });
        }

        const self = SoundResource{
            .intro = data[intro_start..intro_end],
            .loop = data[loop_start..loop_end],
        };

        return self;
    }

    /// Construct a sound resource from a slice of signed audio data,
    /// optionally looping at the specified byte offset.
    /// Intended only for use in tests.
    /// Panics if `loop_at` is beyond the end of sample data.
    pub fn init(sample_data: []const audio.Sample, loop_at: ?usize) SoundResource {
        const unsigned_sample_data = @bitCast([]const u8, sample_data);

        if (loop_at) |loop_start| {
            std.debug.assert(loop_start < sample_data.len);
            return .{
                .intro = unsigned_sample_data[0..loop_start],
                .loop = unsigned_sample_data[loop_start..],
            };
        } else {
            return .{
                .intro = unsigned_sample_data,
                .loop = unsigned_sample_data[sample_data.len..sample_data.len],
            };
        }
    }

    /// Given a byte offset, returns the sample at that offset in the sound data.
    /// If the sound is looped, offsets beyond the end of sound data will loop
    /// around to the start of the looped section.
    /// If the sound is not looped, offsets beyond the end of sound data will
    /// return `null`.
    pub fn sampleAt(self: SoundResource, offset: Offset) ?audio.Sample {
        if (offset < self.intro.len) {
            return @bitCast(audio.Sample, self.intro[offset]);
        } else if (self.loop.len > 0) {
            const offset_within_loop = (offset - self.intro.len) % self.loop.len;
            return @bitCast(audio.Sample, self.loop[offset_within_loop]);
        } else {
            return null;
        }
    }

    /// Given a byte offset and a sub-byte fractional offset, returns the sample
    /// at that offset linearly interpolated with the following sample according
    /// to the fractional ratio.
    /// If the sound is looped, offsets beyond the sound data will interpolate
    /// from the end back to the start of the looped section.
    /// If the sound is not looped, offsets at the end of the sound data will
    /// be interpolated with silence. Offsets beyond the end of the sound data
    /// will return `null`.
    pub fn interpolatedSampleAt(self: SoundResource, offset: Offset, fraction: FractionalOffset) ?audio.Sample {
        // If the sample falls beyond the end of the sound, stop playing immediately.
        const start_sample = self.sampleAt(offset) orelse return null;
        // If the following sample falls beyond the end of the sound, return the original sample as-is.
        const end_sample = self.sampleAt(offset + 1) orelse return start_sample;

        // Mix the two samples together according to the fractional ratio.
        return interpolation.interpolate(audio.Sample, start_sample, end_sample, fraction);
    }

    pub const Offset = usize;
    pub const FractionalOffset = interpolation.Ratio;

    pub const ParseError = error{
        /// The slice provided to SoundResource.parse was too short to hold the header,
        /// or too short to hold the intro and loop section described in the header.
        TruncatedData,
    };
};

/// Data offsets within a sound effect resource.
const DataLayout = struct {
    const intro_length = 0x00;
    const loop_length = 0x02;
    const unused = 0x04;
    const intro = 0x08;
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
    try testing.expectEqual(fixture[8..14], sound.intro);
    try testing.expectEqual(0, sound.loop.len);
}

test "parse correctly parses sound data with only loop" {
    const fixture = &Fixtures.loop_only;
    const sound = try SoundResource.parse(fixture);
    try testing.expectEqual(0, sound.intro.len);
    try testing.expectEqual(fixture[8..12], sound.loop);
}

test "parse correctly parses sound data with intro and loop" {
    const fixture = &Fixtures.intro_with_loop;
    const sound = try SoundResource.parse(fixture);

    try testing.expectEqual(fixture[8..14], sound.intro);
    try testing.expectEqual(fixture[14..18], sound.loop);
}

test "parse correctly parses empty sound data" {
    const fixture = &Fixtures.empty;
    const sound = try SoundResource.parse(fixture);
    try testing.expectEqual(0, sound.intro.len);
    try testing.expectEqual(0, sound.loop.len);
}

test "parse correctly parses data that is longer than necessary" {
    const padded_fixture = &(Fixtures.intro_with_loop ++ [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04 });
    const sound = try SoundResource.parse(padded_fixture);

    try testing.expectEqual(padded_fixture[8..14], sound.intro);
    try testing.expectEqual(padded_fixture[14..18], sound.loop);
}

test "parse correctly parses sound data that has the maximum expressible length" {
    var fixture = try testing.allocator.alloc(u8, 262148);
    defer testing.allocator.free(fixture);

    std.mem.copy(u8, fixture[0..8], &[_]u8{
        0xFF, 0xFF, // Intro data is 65535 words (131070 bytes) long
        0xFF, 0xFF, // Loop data is 65535 words (131070 bytes) long
        // Rest of header is unused
        0x00, 0x00,
        0x00, 0x00,
    });

    const sound = try SoundResource.parse(fixture);
    try testing.expectEqual(fixture[8..131078], sound.intro);
    try testing.expectEqual(fixture[131078..262148], sound.loop);
}

test "parse returns error.TruncatedData for data too short to fit header" {
    const truncated_fixture = Fixtures.intro_with_loop[0..4];
    try testing.expectError(error.TruncatedData, SoundResource.parse(truncated_fixture));
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

test "sampleAt on intro-only sound returns intro data for in-range offsets and null for out-of-range offsets" {
    const sound = SoundResource.init(&[_]audio.Sample{ 0, -2, 4, -6, 8 }, null);

    try testing.expectEqual(0, sound.sampleAt(0));
    try testing.expectEqual(-2, sound.sampleAt(1));
    try testing.expectEqual(4, sound.sampleAt(2));
    try testing.expectEqual(-6, sound.sampleAt(3));
    try testing.expectEqual(8, sound.sampleAt(4));
    try testing.expectEqual(null, sound.sampleAt(5));
}

test "sampleAt on loop-only sound loops over looped data indefinitely" {
    const sound = SoundResource.init(&[_]audio.Sample{ 0, -2, 4, -6, 8 }, 0);

    try testing.expectEqual(0, sound.sampleAt(0));
    try testing.expectEqual(-2, sound.sampleAt(1));
    try testing.expectEqual(4, sound.sampleAt(2));
    try testing.expectEqual(-6, sound.sampleAt(3));
    try testing.expectEqual(8, sound.sampleAt(4));
    try testing.expectEqual(0, sound.sampleAt(5));
    try testing.expectEqual(-2, sound.sampleAt(6));
    try testing.expectEqual(4, sound.sampleAt(7));
    try testing.expectEqual(-6, sound.sampleAt(8));
    try testing.expectEqual(8, sound.sampleAt(9));
}

test "sampleAt on intro-with-loop sound returns intro data then loops over looped data indefinitely" {
    const sound = SoundResource.init(&[_]audio.Sample{ 0, -2, 4, -6, 8 }, 3);

    try testing.expectEqual(0, sound.sampleAt(0));
    try testing.expectEqual(-2, sound.sampleAt(1));
    try testing.expectEqual(4, sound.sampleAt(2));
    try testing.expectEqual(-6, sound.sampleAt(3));
    try testing.expectEqual(8, sound.sampleAt(4));
    try testing.expectEqual(-6, sound.sampleAt(5));
    try testing.expectEqual(8, sound.sampleAt(6));
    try testing.expectEqual(-6, sound.sampleAt(7));
    try testing.expectEqual(8, sound.sampleAt(8));
    try testing.expectEqual(-6, sound.sampleAt(9));
}

test "sampleAt returns null for empty sounds" {
    const sound = SoundResource.init(&[_]audio.Sample{}, null);

    try testing.expectEqual(null, sound.sampleAt(0));
    try testing.expectEqual(null, sound.sampleAt(1));
}

// - interpolatedSampleAt tests -

test "interpolatedSampleAt interpolates between two adjacent samples" {
    const sound = SoundResource.init(&[_]audio.Sample{ -128, 127 }, null);

    try testing.expectEqual(-128, sound.interpolatedSampleAt(0, 0));
    try testing.expectEqual(-64, sound.interpolatedSampleAt(0, 64));
    try testing.expectEqual(0, sound.interpolatedSampleAt(0, 128));
    try testing.expectEqual(64, sound.interpolatedSampleAt(0, 192));
    try testing.expectEqual(126, sound.interpolatedSampleAt(0, 254));
    try testing.expectEqual(127, sound.interpolatedSampleAt(0, 255));
    try testing.expectEqual(127, sound.interpolatedSampleAt(1, 0));
}

test "interpolatedSampleAt returns final sample at end of unlooped sound" {
    const sound = SoundResource.init(&[_]audio.Sample{127}, null);

    try testing.expectEqual(127, sound.interpolatedSampleAt(0, 0));
    try testing.expectEqual(127, sound.interpolatedSampleAt(0, 64));
    try testing.expectEqual(127, sound.interpolatedSampleAt(0, 128));
    try testing.expectEqual(127, sound.interpolatedSampleAt(0, 192));
    try testing.expectEqual(127, sound.interpolatedSampleAt(0, 255));
    try testing.expectEqual(null, sound.interpolatedSampleAt(1, 0));
}

test "interpolatedSampleAt interpolates across loop boundary" {
    const sound = SoundResource.init(&[_]audio.Sample{ 64, -128, 127 }, 1);

    try testing.expectEqual(127, sound.interpolatedSampleAt(2, 0));
    try testing.expectEqual(63, sound.interpolatedSampleAt(2, 64));
    try testing.expectEqual(-1, sound.interpolatedSampleAt(2, 128));
    try testing.expectEqual(-65, sound.interpolatedSampleAt(2, 192));
    try testing.expectEqual(-128, sound.interpolatedSampleAt(2, 255));
    try testing.expectEqual(-128, sound.interpolatedSampleAt(3, 0));
    try testing.expectEqual(-64, sound.interpolatedSampleAt(3, 64));
    try testing.expectEqual(0, sound.interpolatedSampleAt(3, 128));
    try testing.expectEqual(64, sound.interpolatedSampleAt(3, 192));
    try testing.expectEqual(127, sound.interpolatedSampleAt(3, 255));
}
