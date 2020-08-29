const std = @import("std");

pub const Error = error {
    /// The program was asked to seek to an address beyond the end of the program.
    InvalidAddress,
    /// A read operation unexpectedly encountered the end of the program.
    EndOfProgram,
};

/// An address within a program, stored in bytecode as a 16-bit unsigned integer.
pub const Address = u16;

/// An Another World bytecode program, which maintains a counter to the next instruction to execute.
pub const Program = struct {
    /// The bytecode making up the program.
    bytecode: []const u8,

    /// The address of the next instruction that will be read.
    /// Invariant: this is less than or equal to bytecode.len.
    counter: usize = 0,

    /// Create a new program that will execute from the start of the specified bytecode.
    pub fn init(bytecode: []const u8) Program {
        return Program { .bytecode = bytecode };
    }

    /// Reads an integer of the specified type from the current program counter
    /// and advances the counter by the byte width of the integer.
    /// Returns error.EndOfProgram and leaves the counter at the end of the program
    /// if there are not enough bytes left in the program.
    pub fn read(self: *Program, comptime Integer: type) Error!Integer {
        comptime const byte_width = @sizeOf(Integer);

        const upper_bound = self.counter + byte_width;
        if (upper_bound > self.bytecode.len) {
            self.counter = self.bytecode.len;
            return error.EndOfProgram;
        }

        const slice = self.bytecode[self.counter..upper_bound];
        const int = std.mem.readIntSliceBig(Integer, slice);
        self.counter = upper_bound;

        return int;
    }

    /// Skip n bytes from the program, moving the counter forward by that amount.
    /// Returns error.EndOfProgram and leaves the counter at the end of the program
    /// if there are not enough bytes left in the program to skip the full amount.
    pub fn skip(self: *Program, byte_count: usize) Error!void {
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
    pub fn jump(self: *Program, address: Address) Error!void {
        if (address >= self.bytecode.len) {
            return error.InvalidAddress;
        }

        self.counter = address;
    }
};

/// -- Tests --

const testing = @import("std").testing;

test "read(u8) returns byte at current program counter and advances program counter" {
    const bytecode = [_]u8 { 0xDE, 0xAD, };
    var program = Program.init(&bytecode);

    testing.expectEqual(@intCast(usize, 0), program.counter);
    
    testing.expectEqual(@intCast(u8, 0xDE), try program.read(u8));
    testing.expectEqual(@intCast(usize, 1), program.counter);

    testing.expectEqual(@intCast(u8, 0xAD), try program.read(u8));
    testing.expectEqual(@intCast(usize, 2), program.counter);
}

test "read(u16) returns big-endian u16 at current program counter and advances program counter by 2" {
    const bytecode = [_]u8 { 0xDE, 0xAD, 0xBE, 0xEF, };
    var program = Program.init(&bytecode);

    testing.expectEqual(@intCast(usize, 0), program.counter);
    testing.expectEqual(@intCast(u16, 0xDEAD), try program.read(u16));
    testing.expectEqual(@intCast(usize, 2), program.counter);
    testing.expectEqual(@intCast(u16, 0xBEEF), try program.read(u16));
    testing.expectEqual(@intCast(usize, 4), program.counter);
}

test "read(u16) returns error.EndOfProgram and leaves program counter at end of program when it tries to read beyond end of program" {
    const bytecode = [_]u8 { 0xDE, };
    var program = Program.init(&bytecode);

    testing.expectEqual(@intCast(usize, 0), program.counter);
    testing.expectError(error.EndOfProgram, program.read(u16));
    testing.expectEqual(bytecode.len, program.counter);
}

test "read(i16) returns big-endian i16 at current program counter and advances program counter by 2" {
    const int1: i16 = -18901;   // 0b1011_0110_0010_1011 in two's complement
    const int2: i16 = 3470;     // 0b0000_1101_1000_1110 in two's complement
    const bytecode = [_]u8 {
        0b1011_0110, 0b0010_1011,
        0b0000_1101, 0b1000_1110,
    };
    var program = Program.init(&bytecode);

    testing.expectEqual(@intCast(usize, 0), program.counter);
    testing.expectEqual(int1, try program.read(i16));
    testing.expectEqual(@intCast(usize, 2), program.counter);
    testing.expectEqual(int2, try program.read(i16));
    testing.expectEqual(@intCast(usize, 4), program.counter);
}

test "read() returns error.EndOfProgram and leaves program counter at end of program when it tries to read beyond end of program" {
    const bytecode = [_]u8 { 0xDE, };
    var program = Program.init(&bytecode);

    testing.expectEqual(@intCast(usize, 0), program.counter);
    testing.expectError(error.EndOfProgram, program.read(u16));
    testing.expectEqual(bytecode.len, program.counter);
}

test "skip() advances program counter" {
    const bytecode = [_]u8 { 0xDE, 0xAD, };
    var program = Program.init(&bytecode);

    testing.expectEqual(@intCast(usize, 0), program.counter);
    try program.skip(2);
    testing.expectEqual(@intCast(usize, 2), program.counter);
}

test "skip() returns error.EndOfProgram and leaves program counter at end of program when it tries to read beyond end of program" {
    const bytecode = [_]u8 { 0xDE, 0xAD, };
    var program = Program.init(&bytecode);

    testing.expectEqual(@intCast(usize, 0), program.counter);
    testing.expectError(error.EndOfProgram, program.skip(5));
    testing.expectEqual(@intCast(usize, 2), program.counter);
}

test "jump() moves program counter to specified address" {
    const bytecode = [_]u8 { 0xDE, 0xAD, 0xBE, 0xEF, };
    var program = Program.init(&bytecode);

    try program.jump(3);
    testing.expectEqual(@intCast(usize, 3), program.counter);
    try program.jump(1);
    testing.expectEqual(@intCast(usize, 1), program.counter);
}

test "jump() returns error.InvalidAddress program counter when given address beyond the end of program" {
    const bytecode = [_]u8 { 0xDE, 0xAD, 0xBE, 0xEF };
    var program = Program.init(&bytecode);

    testing.expectError(error.InvalidAddress, program.jump(5));
}