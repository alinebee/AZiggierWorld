const Thread = @import("types/thread.zig");
const ThreadID = @import("types/thread_id.zig");
const Program = @import("types/program.zig");

pub const max_threads = 64;
pub const max_registers = 256;

/// Register values are interpreted as signed 16-bit integers.
pub const RegisterValue = i16;
pub const RegisterID = u8;

pub const Instance = struct {
    /// The current state of the VM's 64 threads.
    threads: [max_threads]Thread.Instance = [_]Thread.Instance { .{} } ** max_threads,

    /// The current state of the VM's 256 registers.
    registers: [max_registers]RegisterValue = [_]RegisterValue { 0 } ** max_registers,

    /// The currently-running program.
    program: Program.Instance,
};

/// A placeholder program to keep tests happy until we flesh out the VM enough
/// to load a real program during its initialization.
const empty_program = [0]u8 {};

pub fn new() Instance {
    var machine = Instance { .program = Program.new(&empty_program) };

    // Initialize the main thread to begin execution at the start of the current program
    machine.threads[ThreadID.main].execution_state = .{ .active = 0 };

    return machine;
}

// -- Tests --

const testing = @import("../utils/testing.zig");

test "init creates new virtual machine with expected state" {
    const machine = new();

    for (machine.threads) |thread, id| {
        if (id == ThreadID.main) {
            testing.expectEqual(.{ .active = 0 }, thread.execution_state);
        } else {
            testing.expectEqual(.inactive, thread.execution_state);
        }
        testing.expectEqual(.running, thread.suspend_state);
    }

    for (machine.registers) |register| {
        testing.expectEqual(0, register);
    }
}
