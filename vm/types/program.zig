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

    /// Returns the byte at the current program counter and advances the counter by 1.
    /// Returns error.EndOfProgram and leaves the counter at the end of the program if there are no more bytes to read.
    pub fn readByte(self: *Program) Error!u8 {
        if (self.counter >= self.bytecode.len) {
            return error.EndOfProgram;
        }

        const byte = self.bytecode[self.counter];
        self.counter += 1;
        return byte;
    }

    /// Returns the unsigned 16-bit integer at the current program counter and advances the counter by 2.
    /// Returns error.EndOfProgram and leaves the counter at the end of the program if there are not
    /// enough bytes for a full 16-bit integer.
    /// This interprets the bytes are big-endian, the convention for Another World's resource files.
    pub fn readU16(self: *Program) Error!u16 {
        const byte1 = try self.readByte();
        const byte2 = try self.readByte();
        return @intCast(u16, byte1) << 8 | @intCast(u16, byte2);
    }

    /// Returns the signed 16-bit integer at the current program counter and advances the counter by 2.
    /// Returns error.EndOfProgram and leaves the counter at the end of the program if there are not enough bytes for a full 16-bit integer.
    /// This interprets the bytes as big-endian and 2's-complement, the convention for Another World's resource files.
    pub fn readI16(self: *Program) Error!i16 {
        return @bitCast(i16, try self.readU16());
    }

    /// Skip n bytes from the program, moving the counter forward by that amount.
    pub fn skip(self: *Program, byte_count: usize) Error!void {
        var count: usize = 0;
        while (count < byte_count) {
            _ = try self.readByte();
            count += 1;
        }
    }

    /// Move the program counter to the specified address,
    /// so that program execution continues from that point.
    pub fn jump(self: *Program, address: Address) Error!void {
        if (address >= self.bytecode.len) {
            return error.InvalidAddress;
        }

        self.counter = address;
    }
};

/// -- Tests --

const testing = @import("std").testing;

test "readByte() returns byte at current program counter and advances program counter" {
    const bytecode = [_]u8 { 0xDE, 0xAD, };
    var program = Program { .bytecode = &bytecode };

    testing.expectEqual(program.counter, 0);
    
    testing.expectEqual(program.readByte(), 0xDE);
    testing.expectEqual(program.counter, 1);

    testing.expectEqual(program.readByte(), 0xAD);
    testing.expectEqual(program.counter, 2);
}

test "readByte() returns error.EndOfProgram and leaves program counter at end of program when it tries to read beyond end of program" {
    const bytecode = [_]u8 { 0xDE, };
    var program = Program.init(&bytecode);

    testing.expectEqual(program.counter, 0);
    _ = try program.readByte();
    testing.expectEqual(program.counter, 1);
    testing.expectError(
        error.EndOfProgram,
        program.readByte(),
    );
    testing.expectEqual(program.counter, bytecode.len);
}

test "readU16() returns big-endian u16 at current program counter and advances program counter by 2" {
    const bytecode = [_]u8 { 0xDE, 0xAD, 0xBE, 0xEF, };
    var program = Program.init(&bytecode);

    testing.expectEqual(program.counter, 0);
    testing.expectEqual(program.readU16(), 0xDEAD);
    testing.expectEqual(program.counter, 2);
    testing.expectEqual(program.readU16(), 0xBEEF);
    testing.expectEqual(program.counter, 4);
}

test "readU16() returns error.EndOfProgram and leaves program counter at end of program when it tries to read beyond end of program" {
    const bytecode = [_]u8 { 0xDE, };
    var program = Program.init(&bytecode);

    testing.expectEqual(program.counter, 0);
    testing.expectError(
        error.EndOfProgram,
        program.readU16(),
    );
    testing.expectEqual(program.counter, bytecode.len);
}

test "readI16() returns big-endian i16 at current program counter and advances program counter by 2" {
    const int1: i16 = -18901;   // 0b1011_0110_0010_1011 in two's complement
    const int2: i16 = 3470;     // 0b0000_1101_1000_1110 in two's complement
    const bytecode = [_]u8 {
        0b1011_0110, 0b0010_1011,
        0b0000_1101, 0b1000_1110,
    };
    var program = Program.init(&bytecode);

    testing.expectEqual(program.counter, 0);
    testing.expectEqual(program.readI16(), int1);
    testing.expectEqual(program.counter, 2);
    testing.expectEqual(program.readI16(), int2);
    testing.expectEqual(program.counter, 4);
}

test "readI16() returns error.EndOfProgram and leaves program counter at end of program when it tries to read beyond end of program" {
    const bytecode = [_]u8 { 0xDE, };
    var program = Program.init(&bytecode);

    testing.expectEqual(program.counter, 0);
    testing.expectError(
        error.EndOfProgram,
        program.readI16(),
    );
    testing.expectEqual(program.counter, bytecode.len);
}

test "skip() advances program counter" {
    const bytecode = [_]u8 { 0xDE, 0xAD, };
    var program = Program.init(&bytecode);

    testing.expectEqual(program.counter, 0);
    try program.skip(2);
    testing.expectEqual(program.counter, 2);
}

test "skip() returns error.EndOfProgram and leaves program counter at end of program when it tries to read beyond end of program" {
    const bytecode = [_]u8 { 0xDE, 0xAD, };
    var program = Program.init(&bytecode);

    testing.expectEqual(program.counter, 0);
    testing.expectError(
        error.EndOfProgram,
        program.skip(5),
    );
    testing.expectEqual(program.counter, 2);
}

test "jump() moves program counter to specified address" {
    const bytecode = [_]u8 { 0xDE, 0xAD, 0xBE, 0xEF, };
    var program = Program.init(&bytecode);

    try program.jump(3);
    testing.expectEqual(program.counter, 3);
    try program.jump(1);
    testing.expectEqual(program.counter, 1);
}

test "jump() returns error.InvalidAddress program counter when given address beyond the end of program" {
    const bytecode = [_]u8 { 0xDE, 0xAD, 0xBE, 0xEF };
    var program = Program.init(&bytecode);

    testing.expectError(
        error.InvalidAddress,
        program.jump(5),
    );
}