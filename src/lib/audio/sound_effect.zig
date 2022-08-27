const std = @import("std");
const anotherworld = @import("../anotherworld.zig");
const log = anotherworld.log;

/// Another World sound effect data has the following layout:
// (Byte offset, size, purpose, description)
// ------HEADER------
// 0..2  u16     length in 16-bit words of intro section
// 2..4  u16     length in 16-bit words of loop section
// 4..8  unused
// ------DATA------
// 8..loop_section_start    u8[]    start of intro data
// loop_section_start..end  u8[]    start of looped data

pub const SoundEffect = struct {
    /// The non-repeated intro section of the sound effect.
    /// Once this plays through, the sample will move on to the looped section.
    /// Null if the sound effect loops without an intro.
    intro: ?[]const u8,
    /// The looped section of the sound effect.
    /// Null if the sound effect does not loop.
    loop: ?[]const u8,

    pub fn parse(data: []const u8) ParseError!SoundEffect {
        if (data.len < header_length) return error.TruncatedData;

        const intro_length_in_words = @intCast(usize, std.mem.readInt(u16, data[0..2], .Big));
        const loop_length_in_words = @intCast(usize, std.mem.readInt(u16, data[2..4], .Big));

        const intro_start = header_length;
        const intro_end = intro_start + (intro_length_in_words * 2);

        const loop_start = intro_end;
        const loop_end = loop_start + (loop_length_in_words * 2);

        if (data.len < loop_end) return error.TruncatedData;
        if (data.len > loop_end) {
            log.debug("Slice too long for expected data: {} actual vs {} expected", .{ data.len, loop_end });
        }

        const self = SoundEffect{
            .intro = if (intro_end > intro_start) data[intro_start..intro_end] else null,
            .loop = if (loop_end > loop_start) data[loop_start..loop_end] else null,
        };

        if (self.intro == null and self.loop == null) {
            log.debug("Empty sound effect", .{});
        }

        return self;
    }

    const header_length = 8;

    pub const ParseError = error{
        // The slice provided to SoundEffect.parse was too short to hold the header,
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
    const sound = try SoundEffect.parse(fixture);
    try testing.expectEqual(fixture[8..14], sound.intro);
    try testing.expectEqual(null, sound.loop);
}

test "init parses sound data with only loop" {
    const fixture = &Fixtures.loop_only;
    const sound = try SoundEffect.parse(fixture);
    try testing.expectEqual(null, sound.intro);
    try testing.expectEqual(fixture[8..12], sound.loop);
}

test "init parses sound data with intro and loop" {
    const fixture = &Fixtures.intro_with_loop;
    const sound = try SoundEffect.parse(fixture);
    try testing.expectEqual(fixture[8..14], sound.intro);
    try testing.expectEqual(fixture[14..], sound.loop);
}

test "init parsed data that is longer than necessary" {
    // Still to verify: whether any sound effect resources in the DOS game are too long for their sample data.
    const padded_fixture = &(Fixtures.intro_with_loop ++ [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04 });
    const sound = try SoundEffect.parse(padded_fixture);
    try testing.expectEqual(padded_fixture[8..14], sound.intro);
    try testing.expectEqual(padded_fixture[14..18], sound.loop);
}

test "init returns error.TruncatedData for data too short to fit header" {
    const truncated_fixture = Fixtures.intro_with_loop[0..4];
    try testing.expectError(error.TruncatedData, SoundEffect.parse(truncated_fixture));
}

test "init returns error.TruncatedData for data too short to fit intro length for intro-only sound effect" {
    const truncated_fixture = Fixtures.intro_only[0 .. Fixtures.intro_only.len - 1];
    try testing.expectError(error.TruncatedData, SoundEffect.parse(truncated_fixture));
}

test "init returns error.TruncatedData for data too short to fit loop length for looped sound effect" {
    const truncated_fixture = Fixtures.loop_only[0 .. Fixtures.loop_only.len - 1];
    try testing.expectError(error.TruncatedData, SoundEffect.parse(truncated_fixture));
}

test "init returns error.TruncatedData for data too short to fit loop length for sound effect with intro and loop" {
    const truncated_fixture = Fixtures.intro_with_loop[0 .. Fixtures.intro_with_loop.len - 1];
    try testing.expectError(error.TruncatedData, SoundEffect.parse(truncated_fixture));
}
