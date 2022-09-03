const anotherworld = @import("../anotherworld.zig");
const timing = anotherworld.timing;

/// The ID of one of 40 preset frequencies. Used by instructions that play sound effects.
pub const FrequencyID = enum(u8) {
    _,

    /// The size of a frequency ID as represented in bytecode.
    pub const Raw = u8;

    pub fn parse(raw: Raw) Error!FrequencyID {
        if (raw >= frequencies.len) return error.InvalidFrequencyID;
        return @intToEnum(FrequencyID, raw);
    }

    pub fn frequency(self: FrequencyID) timing.Hz {
        return frequencies[@enumToInt(self)];
    }

    /// Converted from hexadecimal reference implementation:
    /// https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/staticres.cpp#L61-L67
    const frequencies = [40]timing.Hz{
        3327,
        3523,
        3729,
        3951,
        4182,
        4430,
        4697,
        4972,
        5279,
        5593,
        5926,
        6280,
        6653,
        7046,
        7457,
        7902,
        8363,
        8860,
        9395,
        9943,
        10559,
        11186,
        11852,
        12560,
        13307,
        14093,
        14915,
        15839,
        16727,
        17720,
        18840,
        19886,
        21056,
        22372,
        23706,
        25032,
        26515,
        28185,
        29829,
        31677,
    };

    pub const Error = error{
        /// Bytecode specified a frequency ID that was out of range.
        InvalidFrequencyID,
    };
};

// -- Testing --

const testing = @import("utils").testing;

test "Everything compiles" {
    testing.refAllDecls(FrequencyID);
}
