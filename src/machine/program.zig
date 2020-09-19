const readIntSliceBig = @import("std").mem.readIntSliceBig;
const introspection = @import("../utils/introspection.zig");

const Address = @import("../values/address.zig");

pub const Error = error{
    /// The program was asked to seek to an address beyond the end of the program.
    InvalidAddress,
    /// A read operation unexpectedly encountered the end of the program.
    EndOfProgram,
};

/// An Another World bytecode program, which maintains a counter to the next instruction to execute.
pub const Instance = struct {
    // This is essentially a read-only `FixedBufferStream` with a more limited
    // and prescriptive API; the only behavioural difference is that it does
    // bounds-checking on seek (jump/skip) operations, not just on read.
    /// The bytecode making up the program.
    bytecode: []const u8,

    /// The address of the next instruction that will be read.
    /// Invariant: this is less than or equal to bytecode.len.
    counter: Address.Native = 0,

    /// Reads an integer of the specified type from the current program counter
    /// and advances the counter by the byte width of the integer.
    /// Returns error.EndOfProgram and leaves the counter at the end of the program
    /// if there are not enough bytes left in the program.
    pub fn read(self: *Instance, comptime Integer: type) Error!Integer {
        // readIntSliceBig uses this construction internally.
        // @sizeOf would be nicer, but may include padding bytes.
        comptime const byte_width = @divExact(introspection.bitCount(Integer), 8);

        const upper_bound = self.counter + byte_width;
        if (upper_bound > self.bytecode.len) {
            self.counter = self.bytecode.len;
            return error.EndOfProgram;
        }

        const slice = self.bytecode[self.counter..upper_bound];
        const int = readIntSliceBig(Integer, slice);
        self.counter = upper_bound;

        return int;
    }

    /// Skip n bytes from the program, moving the counter forward by that amount.
    /// Returns error.EndOfProgram and leaves the counter at the end of the program
    /// if there are not enough bytes left in the program to skip the full amount.
    pub fn skip(self: *Instance, byte_count: usize) Error!void {
        const upper_bound = self.counter + byte_count;
        if (upper_bound > self.bytecode.len) {
            self.counter = self.bytecode.len;
            return error.EndOfProgram;
        }
        self.counter = upper_bound;
    }

    /// Move the program counter to the specified address,
    /// so that program execution continues from that point.
    /// Returns error.InvalidAddress if the address is beyond the end of the program.
    pub fn jump(self: *Instance, address: Address.Native) Error!void {
        if (address >= self.bytecode.len) {
            return error.InvalidAddress;
        }

        self.counter = address;
    }
};

/// Create a new program that will execute from the start of the specified bytecode.
pub fn new(bytecode: []const u8) Instance {
    return .{ .bytecode = bytecode };
}

/// -- Tests --
const testing = @import("../utils/testing.zig");

test "read(u8) returns byte at current program counter and advances program counter" {
    const bytecode = [_]u8{ 0xDE, 0xAD };
    var program = new(&bytecode);

    testing.expectEqual(0, program.counter);

    testing.expectEqual(0xDE, program.read(u8));
    testing.expectEqual(1, program.counter);

    testing.expectEqual(0xAD, program.read(u8));
    testing.expectEqual(2, program.counter);
}

test "read(u16) returns big-endian u16 at current program counter and advances program counter by 2" {
    const bytecode = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    var program = new(&bytecode);

    testing.expectEqual(0, program.counter);
    testing.expectEqual(0xDEAD, program.read(u16));
    testing.expectEqual(2, program.counter);
    testing.expectEqual(0xBEEF, program.read(u16));
    testing.expectEqual(4, program.counter);
}

test "read(u16) returns error.EndOfProgram and leaves program counter at end of program when it tries to read beyond end of program" {
    const bytecode = [_]u8{0xDE};
    var program = new(&bytecode);

    testing.expectEqual(0, program.counter);
    testing.expectError(error.EndOfProgram, program.read(u16));
    testing.expectEqual(bytecode.len, program.counter);
}

test "read(i16) returns big-endian i16 at current program counter and advances program counter by 2" {
    const int1: i16 = -18901; // 0b1011_0110_0010_1011 in two's complement
    const int2: i16 = 3470; // 0b0000_1101_1000_1110 in two's complement
    const bytecode = [_]u8{
        0b1011_0110, 0b0010_1011,
        0b0000_1101, 0b1000_1110,
    };
    var program = new(&bytecode);

    testing.expectEqual(0, program.counter);
    testing.expectEqual(int1, program.read(i16));
    testing.expectEqual(2, program.counter);
    testing.expectEqual(int2, program.read(i16));
    testing.expectEqual(4, program.counter);
}

test "read() returns error.EndOfProgram and leaves program counter at end of program when it tries to read beyond end of program" {
    const bytecode = [_]u8{0xDE};
    var program = new(&bytecode);

    testing.expectEqual(0, program.counter);
    testing.expectError(error.EndOfProgram, program.read(u16));
    testing.expectEqual(bytecode.len, program.counter);
}

test "skip() advances program counter" {
    const bytecode = [_]u8{ 0xDE, 0xAD };
    var program = new(&bytecode);

    testing.expectEqual(0, program.counter);
    try program.skip(2);
    testing.expectEqual(2, program.counter);
}

test "skip() returns error.EndOfProgram and leaves program counter at end of program when it tries to read beyond end of program" {
    const bytecode = [_]u8{ 0xDE, 0xAD };
    var program = new(&bytecode);

    testing.expectEqual(0, program.counter);
    testing.expectError(error.EndOfProgram, program.skip(5));
    testing.expectEqual(2, program.counter);
}

test "jump() moves program counter to specified address" {
    const bytecode = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    var program = new(&bytecode);

    try program.jump(3);
    testing.expectEqual(3, program.counter);
    try program.jump(1);
    testing.expectEqual(1, program.counter);
}

test "jump() returns error.InvalidAddress program counter when given address beyond the end of program" {
    const bytecode = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    var program = new(&bytecode);

    testing.expectError(error.InvalidAddress, program.jump(6));
}
