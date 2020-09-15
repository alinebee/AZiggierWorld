const StringID = @import("string_id.zig");

pub const Error = StringID.Error;

const Entry = struct {
    id: StringID.Raw,
    string: []const u8,
};

/// A table of UI strings.
const Table = struct {
    entries: []const Entry,

    /// Given a string table, returns the UI string in the table that corresponds to the specified string identifier.
    /// Returns an error if the string could not be found.
    pub fn find(self: Table, id: StringID.Raw) Error![]const u8 {
        for (self.entries) |entry| {
            if (entry.id == id) {
                return entry.string;
            }
        } else {
            return error.InvalidStringID;
        }
    }
};

/// The UI strings from the full DOS English release of the game.
pub const english = Table{
    .entries = &[_]Entry{
        .{ .id = 0x001, .string = "P E A N U T  3000" },
        .{ .id = 0x002, .string = "Copyright  } 1990 Peanut Computer, Inc.\nAll rights reserved.\n\nCDOS Version 5.01" },
        .{ .id = 0x003, .string = "2" },
        .{ .id = 0x004, .string = "3" },
        .{ .id = 0x005, .string = "." },
        .{ .id = 0x006, .string = "A" },
        .{ .id = 0x007, .string = "@" },
        .{ .id = 0x008, .string = "PEANUT 3000" },

        .{ .id = 0x00A, .string = "R" },
        .{ .id = 0x00B, .string = "U" },
        .{ .id = 0x00C, .string = "N" },
        .{ .id = 0x00D, .string = "P" },
        .{ .id = 0x00E, .string = "R" },
        .{ .id = 0x00F, .string = "O" },
        .{ .id = 0x010, .string = "J" },
        .{ .id = 0x011, .string = "E" },
        .{ .id = 0x012, .string = "C" },
        .{ .id = 0x013, .string = "T" },
        .{ .id = 0x014, .string = "Shield 9A.5f Ok" },
        .{ .id = 0x015, .string = "Flux % 5.0177 Ok" },
        .{ .id = 0x016, .string = "CDI Vector ok" },
        .{ .id = 0x017, .string = " %%%ddd ok" },
        .{ .id = 0x018, .string = "Race-Track ok" },
        .{ .id = 0x019, .string = "SYNCHROTRON" },
        .{ .id = 0x01A, .string = "E: 23%\ng: .005\n\nRK: 77.2L\n\nopt: g+\n\n Shield:\n1: OFF\n2: ON\n3: ON\n\nP~: 1\n" },
        .{ .id = 0x01B, .string = "ON" },
        .{ .id = 0x01C, .string = "-" },

        .{ .id = 0x021, .string = "|" },
        .{ .id = 0x022, .string = "--- Theoretical study ---" },
        .{ .id = 0x023, .string = " THE EXPERIMENT WILL BEGIN IN    SECONDS" },
        .{ .id = 0x024, .string = "  20" },
        .{ .id = 0x025, .string = "  19" },
        .{ .id = 0x026, .string = "  18" },
        .{ .id = 0x027, .string = "  4" },
        .{ .id = 0x028, .string = "  3" },
        .{ .id = 0x029, .string = "  2" },
        .{ .id = 0x02A, .string = "  1" },
        .{ .id = 0x02B, .string = "  0" },
        .{ .id = 0x02C, .string = "L E T ' S   G O" },

        .{ .id = 0x031, .string = "- Phase 0:\nINJECTION of particles\ninto synchrotron" },
        .{ .id = 0x032, .string = "- Phase 1:\nParticle ACCELERATION." },
        .{ .id = 0x033, .string = "- Phase 2:\nEJECTION of particles\non the shield." },
        .{ .id = 0x034, .string = "A  N  A  L  Y  S  I  S" },
        .{ .id = 0x035, .string = "- RESULT:\nProbability of creating:\n ANTIMATTER: 91.V %\n NEUTRINO 27:  0.04 %\n NEUTRINO 424: 18 %\n" },
        .{ .id = 0x036, .string = "   Practical verification Y/N ?" },
        .{ .id = 0x037, .string = "SURE ?" },
        .{ .id = 0x038, .string = "MODIFICATION OF PARAMETERS\nRELATING TO PARTICLE\nACCELERATOR (SYNCHROTRON)." },
        .{ .id = 0x039, .string = "       RUN EXPERIMENT ?" },

        .{ .id = 0x03C, .string = "t---t" },
        .{ .id = 0x03D, .string = "000 ~" },
        .{ .id = 0x03E, .string = ".20x14dd" },
        .{ .id = 0x03F, .string = "gj5r5r" },
        .{ .id = 0x040, .string = "tilgor 25%" },
        .{ .id = 0x041, .string = "12% 33% checked" },
        .{ .id = 0x042, .string = "D=4.2158005584" },
        .{ .id = 0x043, .string = "d=10.00001" },
        .{ .id = 0x044, .string = "+" },
        .{ .id = 0x045, .string = "*" },
        .{ .id = 0x046, .string = "% 304" },
        .{ .id = 0x047, .string = "gurgle 21" },
        .{ .id = 0x048, .string = "{{{{" },
        .{ .id = 0x049, .string = "Delphine Software" },
        .{ .id = 0x04A, .string = "By Eric Chahi" },
        .{ .id = 0x04B, .string = "  5" },
        .{ .id = 0x04C, .string = "  17" },

        .{ .id = 0x12C, .string = "0" },
        .{ .id = 0x12D, .string = "1" },
        .{ .id = 0x12E, .string = "2" },
        .{ .id = 0x12F, .string = "3" },
        .{ .id = 0x130, .string = "4" },
        .{ .id = 0x131, .string = "5" },
        .{ .id = 0x132, .string = "6" },
        .{ .id = 0x133, .string = "7" },
        .{ .id = 0x134, .string = "8" },
        .{ .id = 0x135, .string = "9" },
        .{ .id = 0x136, .string = "A" },
        .{ .id = 0x137, .string = "B" },
        .{ .id = 0x138, .string = "C" },
        .{ .id = 0x139, .string = "D" },
        .{ .id = 0x13A, .string = "E" },
        .{ .id = 0x13B, .string = "F" },
        .{ .id = 0x13C, .string = "        ACCESS CODE:" },
        .{ .id = 0x13D, .string = "PRESS BUTTON OR RETURN TO CONTINUE" },
        .{ .id = 0x13E, .string = "   ENTER ACCESS CODE" },
        .{ .id = 0x13F, .string = "   INVALID PASSWORD !" },
        .{ .id = 0x140, .string = "ANNULER" },
        .{ .id = 0x141, .string = "      INSERT DISK ?\n\n\n\n\n\n\n\n\nPRESS ANY KEY TO CONTINUE" },
        .{ .id = 0x142, .string = " SELECT SYMBOLS CORRESPONDING TO\n THE POSITION\n ON THE CODE WHEEL" },
        .{ .id = 0x143, .string = "    LOADING..." },
        .{ .id = 0x144, .string = "              ERROR" },

        .{ .id = 0x15E, .string = "LDKD" },
        .{ .id = 0x15F, .string = "HTDC" },
        .{ .id = 0x160, .string = "CLLD" },
        .{ .id = 0x161, .string = "FXLC" },
        .{ .id = 0x162, .string = "KRFK" },
        .{ .id = 0x163, .string = "XDDJ" },
        .{ .id = 0x164, .string = "LBKG" },
        .{ .id = 0x165, .string = "KLFB" },
        .{ .id = 0x166, .string = "TTCT" },
        .{ .id = 0x167, .string = "DDRX" },
        .{ .id = 0x168, .string = "TBHK" },
        .{ .id = 0x169, .string = "BRTD" },
        .{ .id = 0x16A, .string = "CKJL" },
        .{ .id = 0x16B, .string = "LFCK" },
        .{ .id = 0x16C, .string = "BFLX" },
        .{ .id = 0x16D, .string = "XJRT" },
        .{ .id = 0x16E, .string = "HRTB" },
        .{ .id = 0x16F, .string = "HBHK" },
        .{ .id = 0x170, .string = "JCGB" },
        .{ .id = 0x171, .string = "HHFL" },
        .{ .id = 0x172, .string = "TFBB" },
        .{ .id = 0x173, .string = "TXHF" },
        .{ .id = 0x174, .string = "JHJL" },

        .{ .id = 0x181, .string = " BY" },
        .{ .id = 0x182, .string = "ERIC CHAHI" },
        .{ .id = 0x183, .string = "         MUSIC AND SOUND EFFECTS" },
        .{ .id = 0x184, .string = " " },
        .{ .id = 0x185, .string = "JEAN-FRANCOIS FREITAS" },
        .{ .id = 0x186, .string = "IBM PC VERSION" },
        .{ .id = 0x187, .string = "      BY" },
        .{ .id = 0x188, .string = " DANIEL MORAIS" },

        .{ .id = 0x18B, .string = "       THEN PRESS FIRE" },
        .{ .id = 0x18C, .string = " PUT THE PADDLE ON THE UPPER LEFT CORNER" },
        .{ .id = 0x18D, .string = "PUT THE PADDLE IN CENTRAL POSITION" },
        .{ .id = 0x18E, .string = "PUT THE PADDLE ON THE LOWER RIGHT CORNER" },

        .{ .id = 0x258, .string = "      Designed by ..... Eric Chahi" },
        .{ .id = 0x259, .string = "    Programmed by...... Eric Chahi" },
        .{ .id = 0x25A, .string = "      Artwork ......... Eric Chahi" },
        .{ .id = 0x25B, .string = "Music by ........ Jean-francois Freitas" },
        .{ .id = 0x25C, .string = "            Sound effects" },
        .{ .id = 0x25D, .string = "        Jean-Francois Freitas\n             Eric Chahi" },

        .{ .id = 0x263, .string = "              Thanks To" },
        .{ .id = 0x264, .string = "           Jesus Martinez\n\n          Daniel Morais\n\n        Frederic Savoir\n\n      Cecile Chahi\n\n    Philippe Delamarre\n\n  Philippe Ulrich\n\nSebastien Berthet\n\nPierre Gousseau" },
        .{ .id = 0x265, .string = "Now Go Out Of This World" },

        .{ .id = 0x190, .string = "Good evening professor." },
        .{ .id = 0x191, .string = "I see you have driven here in your\nFerrari." },
        .{ .id = 0x192, .string = "IDENTIFICATION" },
        .{ .id = 0x193, .string = "Monsieur est en parfaite sante." },
        .{ .id = 0x194, .string = "Y\n" },
        .{ .id = 0x193, .string = "AU BOULOT !!!\n" },
    },
};

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "find returns string for valid identifier" {
    testing.expectEqual("L E T ' S   G O", english.find(0x02C));
}

test "find returns error.InvalidStringID for unknown identifier" {
    testing.expectError(error.InvalidStringID, english.find(0x02F));
}
