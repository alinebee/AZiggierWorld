const Address = @import("program.zig").Address;

pub const ExecutionState = union(enum) {
    /// The thread is active and will continue execution from the specified address when it is next run.
    active: Address,

    /// The thread is inactive and cannot run, regardless of whether it is running or suspended.
    inactive,
};

pub const SuspendState = enum {
    /// The thread is not suspended: it will run if it is also active (see `ExecutionState`).
    running,

    /// The thread is paused and will not execute until unsuspended.
    suspended,
};

/// The maximum number of program instructions that can be executed on a single thread in a single tic
/// before it will abort with an error.
/// Exceeding this number of instructions likely indicates an infinite loop.
const max_executions_per_tic = 10_000;

/// One of the program execution threads within the Another World virtual machine.
/// A thread maintains its own paused/running state and its current program counter.
/// Each tic, the virtual machine runs each active thread: the thread resumes executing the current program
/// starting from the thread's last program counter, and will run until the thread yields to the next thread
/// or deactivates itself.
pub const Instance = struct {
    // Theoretically, a thread can only be in three functional states:
    // 1. Running at program counter X
    // 2. Suspended at program counter X
    // 3. Inactive
    //
    // However, Another World represents these 3 states with two booleans that can be modified independently of each other.
    // So there are actually 4 logical states:
    // 1. Running at program counter X and not suspended
    // 2. Running at program counter X and suspended
    // 3. Inactive and not suspended
    // 4. Inactive and suspended
    // States 3 and 4 have the same effect; but we cannot rule out that a program will suspend an inactive thread, then start running the thread *but expect it to remain suspended*. To allow that, we must track each variable independently.

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
    pub fn scheduleJump(self: *Instance, address: Address) void {
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
};

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "scheduleJump schedules activation with specified program counter for next tic" {
    var thread = Instance { };

    thread.scheduleJump(0xDEAD);

    testing.expectEqual(.inactive, thread.execution_state);
    testing.expectEqual(.{ .active = 0xDEAD }, thread.scheduled_execution_state);
}

test "scheduleDeactivate schedules deactivation for next tic" {
    var thread = Instance { .execution_state = .{ .active = 0xDEAD } };

    thread.scheduleDeactivate();

    testing.expectEqual(.{ .active = 0xDEAD }, thread.execution_state);
    testing.expectEqual(.inactive, thread.scheduled_execution_state);
}

test "scheduleResume schedules resuming for next tic" {
    var thread = Instance { .suspend_state = .suspended };

    thread.scheduleResume();

    testing.expectEqual(.suspended, thread.suspend_state);
    testing.expectEqual(.running, thread.scheduled_suspend_state);
}

test "scheduleSuspend schedules suspending for next tic" {
    var thread = Instance { };

    thread.scheduleSuspend();

    testing.expectEqual(.running, thread.suspend_state);
    testing.expectEqual(.suspended, thread.scheduled_suspend_state);
}

test "update applies scheduled execution state" {
    var thread = Instance { };

    thread.scheduleJump(0xDEAD);
    testing.expectEqual(.inactive, thread.execution_state);
    testing.expectEqual(.{ .active = 0xDEAD }, thread.scheduled_execution_state);

    thread.update();
    testing.expectEqual(.{ .active = 0xDEAD }, thread.execution_state);
    testing.expectEqual(null, thread.scheduled_execution_state);

    thread.scheduleDeactivate();
    testing.expectEqual(.{ .active = 0xDEAD }, thread.execution_state);
    testing.expectEqual(.inactive, thread.scheduled_execution_state);

    thread.update();
    testing.expectEqual(.inactive, thread.execution_state);
    testing.expectEqual(null, thread.scheduled_execution_state);
}

test "update applies scheduled suspend state" {
    var thread = Instance { };

    testing.expectEqual(.running, thread.suspend_state);
    testing.expectEqual(null, thread.scheduled_suspend_state);

    thread.scheduleSuspend();
    testing.expectEqual(.running, thread.suspend_state);
    testing.expectEqual(.suspended, thread.scheduled_suspend_state);

    thread.update();
    testing.expectEqual(.suspended, thread.suspend_state);
    testing.expectEqual(null, thread.scheduled_suspend_state);

    thread.scheduleResume();
    testing.expectEqual(.suspended, thread.suspend_state);
    testing.expectEqual(.running, thread.scheduled_suspend_state);

    thread.update();
    testing.expectEqual(.running, thread.suspend_state);
    testing.expectEqual(null, thread.scheduled_suspend_state);
}
