const anotherworld = @import("../anotherworld.zig");
const timing = anotherworld.timing;

const _Raw = u8;

/// The ID of one of 40 preset frequencies. Used by instructions that play sound effects.
pub const FrequencyID = enum(_Raw) {
    _,

    /// The size of a frequency ID as represented in bytecode.
    pub const Raw = _Raw;

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

test "parse returns FrequencyID for in-range values" {
    try testing.expectEqual(@intToEnum(FrequencyID, 0), try FrequencyID.parse(0));
    try testing.expectEqual(@intToEnum(FrequencyID, 39), try FrequencyID.parse(39));
}

test "parse returns InvalidFrequencyID for out of range values" {
    try testing.expectError(error.InvalidFrequencyID, FrequencyID.parse(40));
}

test "frequency returns Hz value corresponding to frequency ID" {
    for (FrequencyID.frequencies) |frequency, index| {
        const id = try FrequencyID.parse(@intCast(FrequencyID.Raw, index));
        try testing.expectEqual(frequency, id.frequency());
    }
}
