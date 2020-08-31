const fmt = @import("std").fmt;

/// Describes all legal filenames for Another World resource files.
pub const GameFile = union(enum) {
    /// A manifest of where each resource is located within the bank files.
    /// Named `MEMLIST.BIN` in the MS-DOS version.
    resource_list,
    
    /// An archive containing one or more compressed game resources.
    /// Named `BANK01`–`BANK0D` in the MS-DOS version.
    bank: u8,

    /// Takes a destination buffer and fills it with the filename for this file,
    /// as used by the MS-DOS version of Another World.
    /// On success, returns the slice of `destination` that was filled with valid data,
    /// which may be less than `destination.len`. The caller owns the returned slice.
    ///
    /// `destination.len` is expected to be at least `max_dos_name_length`.
    /// Returns an error if `destination` is too small to fit the actual filename:
    /// in this case, `destination` will contain as much of the filename as would fit.
    pub fn printDOSName(self: GameFile, destination: []u8) fmt.BufPrintError![]const u8 {
        return switch (self) {
            .resource_list => fmt.bufPrint(destination, "MEMLIST.BIN", .{}),
            .bank => |id| fmt.bufPrint(destination, "BANK{X:0>2}", .{ id }),
        };
    }
};

/// The maximum length of a filename for the DOS version of the game.
/// DOS filenames comprise an 8-character name, a 3-character extention and a dot separator:
/// i.e. 12345678.EXT
pub const max_dos_name_length = 12;

// -- Tests --

const testing = @import("../utils/testing.zig");

test "printDOSName formats resource_list filename correctly" {
    var buffer: [max_dos_name_length]u8 = undefined;
    const game_file: GameFile = .resource_list;

    testing.expectEqualStrings("MEMLIST.BIN", try game_file.printDOSName(&buffer));
}

test "printDOSName formats single-digit bank filename with correct padding" {
    var buffer: [max_dos_name_length]u8 = undefined;
    const game_file: GameFile = .{ .bank = 3 };

    testing.expectEqualStrings("BANK03", try game_file.printDOSName(&buffer));
}

test "printDOSName formats two-decimal-digit bank filename as hex" {
    var buffer: [max_dos_name_length]u8 = undefined;
    const game_file: GameFile = .{ .bank = 10 };

    testing.expectEqualStrings("BANK0A", try game_file.printDOSName(&buffer));
}

test "printDOSName formats two-hex-digit bank filename as two-digit hex" {
    var buffer: [max_dos_name_length]u8 = undefined;
    const game_file: GameFile = .{ .bank = 0xFE };

    testing.expectEqualStrings("BANKFE", try game_file.printDOSName(&buffer));
}

test "printDOSName returns error when destination buffer was too small" {
    var buffer: [6]u8 = undefined;
    const game_file: GameFile = .resource_list;

    testing.expectError(error.NoSpaceLeft, game_file.printDOSName(&buffer));
    testing.expectEqualStrings("MEMLIS", &buffer);
}
