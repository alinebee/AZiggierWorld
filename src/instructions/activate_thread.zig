const Opcode = @import("../values/opcode.zig");
const ThreadID = @import("../values/thread_id.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");
const Address = @import("../values/address.zig");

pub const opcode = Opcode.Enum.ActivateThread;

/// Activate a specific thread and move its program counter to the specified address.
/// Takes effect on the next iteration of the run loop.
pub const Instance = struct {
    /// The thread to activate.
    thread_id: ThreadID.Trusted,

    /// The program address that the thread should jump to when activated.
    address: Address.Raw,

    pub fn execute(self: Instance, machine: *Machine.Instance) void {
        machine.threads[self.thread_id].scheduleJump(self.address);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 4 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) ParseError!Instance {
    const raw_thread_id = try program.read(ThreadID.Raw);
    const address = try program.read(Address.Raw);

    // Do failable parsing *after* loading all the bytes that this instruction would normally consume;
    // This way, tests that recover from failed parsing will parse the rest of the bytecode correctly.
    return Instance{
        .thread_id = try ThreadID.parse(raw_thread_id),
        .address = address,
    };
}

pub const ParseError = Program.Error || ThreadID.Error;

// -- Bytecode examples --

pub const Fixtures = struct {
    const raw_opcode = @enumToInt(opcode);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [4]u8{ raw_opcode, 63, 0xDE, 0xAD };

    /// Example bytecode with an invalid thread ID that should produce an error.
    const invalid_thread_id = [4]u8{ raw_opcode, 255, 0xDE, 0xAD };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses instruction from valid bytecode and consumes 4 bytes" {
    const instruction = try expectParse(parse, &Fixtures.valid, 4);

    try testing.expectEqual(63, instruction.thread_id);
    try testing.expectEqual(0xDEAD, instruction.address);
}

test "parse returns error.InvalidThreadID and consumes 4 bytes when thread ID is invalid" {
    try testing.expectError(
        error.InvalidThreadID,
        expectParse(parse, &Fixtures.invalid_thread_id, 4),
    );
}

test "execute schedules specified thread to jump to specified address" {
    const instruction = Instance{
        .thread_id = 63,
        .address = 0xDEAD,
    };

    var machine = Machine.testInstance(null);
    defer machine.deinit();

    instruction.execute(&machine);

    try testing.expectEqual(.{ .active = 0xDEAD }, machine.threads[63].scheduled_execution_state);
}
