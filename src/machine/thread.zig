const Address = @import("../values/address.zig");
const Machine = @import("machine.zig");
const execute_next_instruction = @import("instruction.zig");

const ExecutionState = union(enum) {
    /// The thread is active and will continue execution from the specified address when it is next run.
    active: Address.Native,

    /// The thread is inactive and cannot run, regardless of whether it is running or suspended.
    inactive,
};

const SuspendState = enum {
    /// The thread is not suspended: it will run if it is also active (see `ExecutionState`).
    running,

    /// The thread is paused and will not execute until unsuspended.
    suspended,
};

/// The maximum number of program instructions that can be executed on a single thread in a single tic
/// before it will abort with an error.
/// Exceeding this number of instructions likely indicates an infinite loop.
const max_instructions_per_tic = 10_000;

/// One of the program execution threads within the Another World virtual machine.
/// A thread maintains its own paused/running state and its current program counter.
/// Each tic, the virtual machine runs each active thread: the thread resumes executing the current program
/// starting from the thread's previous program counter, and will run until the thread yields to the next
/// thread or deactivates itself.
pub const Instance = struct {
    // Theoretically, a thread can only be in three functional states:
    // 1. Running at program counter X
    // 2. Suspended at program counter X
    // 3. Inactive
    //
    // However, Another World represents these 3 states with two booleans that can be modified
    // independently of each other.
    // So there are actually 4 logical states:
    // 1. Running at program counter X and not suspended
    // 2. Running at program counter X and suspended
    // 3. Inactive and not suspended
    // 4. Inactive and suspended
    // States 3 and 4 have the same effect; but we cannot rule out that a program will suspend
    // an inactive thread, then start running the thread *but expect it to remain suspended*.
    // To allow that, we must track each variable independently.
    /// The active/inactive execution state of this thread during the current game tic.
    execution_state: ExecutionState = .inactive,
    /// The scheduled active/inactive execution state of this thread for the next game tic.
    /// If `null`, the current state will continue unchanged next tic.
    scheduled_execution_state: ?ExecutionState = null,

    /// The running/suspended state of this thread during the current game tic.
    suspend_state: SuspendState = .running,
    /// The scheduled running/suspended state of this thread for the current game tic.
    /// If `null`, the current state will continue unchanged next tic.
    scheduled_suspend_state: ?SuspendState = null,

    /// On the next game tic, activate this thread and jump to the specified address.
    /// If the thread is currently inactive, then it will remain so for the rest of the current tic.
    pub fn scheduleJump(self: *Instance, address: Address.Native) void {
        self.scheduled_execution_state = .{ .active = address };
    }

    /// On the next game tic, deactivate this thread.
    /// If the thread is currently active, then it will remain so for the rest of the current tic.
    pub fn scheduleDeactivate(self: *Instance) void {
        self.scheduled_execution_state = .inactive;
    }

    /// On the next game tic, resume running this thread.
    /// If the thread is currently suspended, then it will remain so for the rest of the current tic.
    pub fn scheduleResume(self: *Instance) void {
        self.scheduled_suspend_state = .running;
    }

    /// On the next game tic, suspend this thread.
    /// If the thread is currently active and running, then it will still run for the current tic if it hasn't already.
    pub fn scheduleSuspend(self: *Instance) void {
        self.scheduled_suspend_state = .suspended;
    }

    /// Apply any excheduled changes to the thread's execution and suspend states.
    pub fn update(self: *Instance) void {
        if (self.scheduled_execution_state) |new_state| {
            self.execution_state = new_state;
            self.scheduled_execution_state = null;
        }

        if (self.scheduled_suspend_state) |new_state| {
            self.suspend_state = new_state;
            self.scheduled_suspend_state = null;
        }
    }

    /// Execute the machine's current program on this thread, running until the thread yields
    /// or deactivates, or an error occurs, or the execution limit is exceeded.
    pub fn run(self: *Instance, machine: *Machine) Error!void {
        // Skip the thread if it's currently paused.
        if (self.suspend_state == .paused) {
            return;
        }

        // If this thread is active, move the shared program counter to the last address for this thread;
        // Otherwise, skip the thread.
        switch (self.execution_state) {
            .active => |address| try machine.program.jump(address),
            .inactive => return,
        }

        // Empty the stack before running each thread.
        machine.stack.clear();

        var instructions_remaining: usize = max_instructions_per_tic;
        while (instructions_remaining > 0) : (instructions_remaining -= 1) {
            const action = try executeNextInstruction(machine.program, machine);
            switch (action) {
                .Continue => continue,
                .Yield => {
                    // Yielding with a non-empty stack would cause the return address
                    // for the current function to be lost after the shared stack gets cleared.
                    // Once the thread resumes executing the function next tic, any Return
                    // instruction within that function would then result in error.StackUnderflow.
                    if (machine.stack.depth > 0) {
                        return error.InvalidYield;
                    }

                    // Record the final position of the program counter so we can resume from there next tic.
                    self.execution_state = .{ .active = machine.program.counter };
                    return;
                },
                .Deactivate => {
                    self.execution_state = .inactive;
                    return;
                },
            }
        } else {
            // If we reach here without returning before now, it means the program got stuck in an infinite loop.
            return error.InstructionLimitExceeded;
        }
    }
};

pub const Error = error{
    /// Bytecode attempted to yield within a function call, which would lose stack information
    // and cause a stack underflow upon resuming and returning from the function.
    InvalidYield,

    /// The thread reached its execution limit without yielding or deactivating.
    /// This would indicate a bytecode bug like an infinite loop.
    InstructionLimitExceeded,
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "scheduleJump schedules activation with specified program counter for next tic" {
    var thread = Instance{};

    thread.scheduleJump(0xDEAD);

    try testing.expectEqual(.inactive, thread.execution_state);
    try testing.expectEqual(.{ .active = 0xDEAD }, thread.scheduled_execution_state);
}

test "scheduleDeactivate schedules deactivation for next tic" {
    var thread = Instance{ .execution_state = .{ .active = 0xDEAD } };

    thread.scheduleDeactivate();

    try testing.expectEqual(.{ .active = 0xDEAD }, thread.execution_state);
    try testing.expectEqual(.inactive, thread.scheduled_execution_state);
}

test "scheduleResume schedules resuming for next tic" {
    var thread = Instance{ .suspend_state = .suspended };

    thread.scheduleResume();

    try testing.expectEqual(.suspended, thread.suspend_state);
    try testing.expectEqual(.running, thread.scheduled_suspend_state);
}

test "scheduleSuspend schedules suspending for next tic" {
    var thread = Instance{};

    thread.scheduleSuspend();

    try testing.expectEqual(.running, thread.suspend_state);
    try testing.expectEqual(.suspended, thread.scheduled_suspend_state);
}

test "update applies scheduled execution state" {
    var thread = Instance{};

    thread.scheduleJump(0xDEAD);
    try testing.expectEqual(.inactive, thread.execution_state);
    try testing.expectEqual(.{ .active = 0xDEAD }, thread.scheduled_execution_state);

    thread.update();
    try testing.expectEqual(.{ .active = 0xDEAD }, thread.execution_state);
    try testing.expectEqual(null, thread.scheduled_execution_state);

    thread.scheduleDeactivate();
    try testing.expectEqual(.{ .active = 0xDEAD }, thread.execution_state);
    try testing.expectEqual(.inactive, thread.scheduled_execution_state);

    thread.update();
    try testing.expectEqual(.inactive, thread.execution_state);
    try testing.expectEqual(null, thread.scheduled_execution_state);
}

test "update applies scheduled suspend state" {
    var thread = Instance{};

    try testing.expectEqual(.running, thread.suspend_state);
    try testing.expectEqual(null, thread.scheduled_suspend_state);

    thread.scheduleSuspend();
    try testing.expectEqual(.running, thread.suspend_state);
    try testing.expectEqual(.suspended, thread.scheduled_suspend_state);

    thread.update();
    try testing.expectEqual(.suspended, thread.suspend_state);
    try testing.expectEqual(null, thread.scheduled_suspend_state);

    thread.scheduleResume();
    try testing.expectEqual(.suspended, thread.suspend_state);
    try testing.expectEqual(.running, thread.scheduled_suspend_state);

    thread.update();
    try testing.expectEqual(.running, thread.suspend_state);
    try testing.expectEqual(null, thread.scheduled_suspend_state);
}
