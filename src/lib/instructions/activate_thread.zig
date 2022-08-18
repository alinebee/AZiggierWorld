const anotherworld = @import("../anotherworld.zig");

const Opcode = @import("opcode.zig").Opcode;
const ThreadID = @import("../../values/thread_id.zig").ThreadID;
const Program = @import("../../machine/program.zig").Program;
const Machine = @import("../../machine/machine.zig").Machine;

/// Activate a specific thread and move its program counter to the specified address.
/// Takes effect on the next iteration of the run loop.
pub const ActivateThread = struct {
    /// The thread to activate.
    thread_id: ThreadID,

    /// The program address that the thread should jump to when activated.
    address: Program.Address,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 4 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const raw_thread_id = try program.read(ThreadID.Raw);
        const address = try program.read(Program.Address);

        // Do failable parsing *after* loading all the bytes that this instruction would normally consume;
        // This way, tests that recover from failed parsing will parse the rest of the bytecode correctly.
        return Self{
            .thread_id = try ThreadID.parse(raw_thread_id),
            .address = address,
        };
    }

    pub fn execute(self: Self, machine: *Machine) ExecutionError!void {
        machine.threads[self.thread_id.index()].scheduleJump(self.address);
    }

    // - Exported constants -

    pub const opcode = Opcode.ActivateThread;
    pub const ExecutionError = error{};
    pub const ParseError = Program.ReadError || ThreadID.Error;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [4]u8{ raw_opcode, 63, 0xDE, 0xAD };

        /// Example bytecode with an invalid thread ID that should produce an error.
        const invalid_thread_id = [4]u8{ raw_opcode, 255, 0xDE, 0xAD };
    };
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;

test "parse parses instruction from valid bytecode and consumes 4 bytes" {
    const instruction = try expectParse(ActivateThread.parse, &ActivateThread.Fixtures.valid, 4);

    try testing.expectEqual(ThreadID.cast(63), instruction.thread_id);
    try testing.expectEqual(0xDEAD, instruction.address);
}

test "parse returns error.InvalidThreadID and consumes 4 bytes when thread ID is invalid" {
    try testing.expectError(
        error.InvalidThreadID,
        expectParse(ActivateThread.parse, &ActivateThread.Fixtures.invalid_thread_id, 4),
    );
}

test "execute schedules specified thread to jump to specified address" {
    const instruction = ActivateThread{
        .thread_id = ThreadID.cast(63),
        .address = 0xDEAD,
    };

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    try instruction.execute(&machine);

    try testing.expectEqual(.{ .active = 0xDEAD }, machine.threads[63].scheduled_execution_state);
}
