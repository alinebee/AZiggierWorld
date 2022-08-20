//! This file defines the state for a thread in the Another World virtual machine.
//!
//! Each thread maintains its own paused/running state and its own program counter.
//! Every tic, the virtual machine runs each active thread in sequence from 0 to 63.
//! Each thread resumes executing the currently loaded program starting from the thread's
//! previous program counter, and will run until an instruction yields to the next thread
//! or deactivates the current thread.
//!
//! Each thread operates on the same bank of global registers; threads are not executed concurrently,
//! so race conditions are not a concern. Separate threads were probably used to to simulate
//! different entities within the game (enemies, projectiles etc.) as well as input-handling
//! and overall housekeeping for the current section of the game.

const anotherworld = @import("../anotherworld.zig");
const bytecode = anotherworld.bytecode;

const Machine = @import("machine.zig").Machine;

const ExecutionState = union(enum) {
    /// The thread is active and will continue execution from the specified address when it is next run.
    active: bytecode.Program.Address,

    /// The thread is inactive and will not run, regardless of whether it is running or paused.
    inactive,
};

const PauseState = enum {
    /// The thread is not paused: it will run if it is also active (see `ExecutionState`).
    running,

    /// The thread is paused and will not execute until unpaused.
    paused,
};

/// One of the program execution threads within the Another World virtual machine.
pub const Thread = struct {
    // Theoretically, a thread can only be in three functional states:
    // 1. Running at program counter X
    // 2. Paused at program counter X
    // 3. Inactive
    //
    // However, Another World represents these 3 states with two booleans that can be modified
    // independently of each other.
    // So there are actually 4 logical states:
    // 1. Active at program counter X and not paused
    // 2. Active at program counter X and paused
    // 3. Inactive and not paused
    // 4. Inactive and paused
    // States 3 and 4 have the same effect; but we cannot rule out that a program will pause
    // an inactive thread, then start running the thread *but expect it to remain paused*.
    // To allow that, we must track each variable independently.

    /// The active/inactive execution state of this thread during the current game tic.
    execution_state: ExecutionState = .inactive,

    /// The scheduled active/inactive execution state of this thread for the next game tic.
    /// If `null`, the current state will continue unchanged next tic.
    scheduled_execution_state: ?ExecutionState = null,

    /// The running/paused state of this thread during the current game tic.
    pause_state: PauseState = .running,

    /// The scheduled running/paused state of this thread for the next game tic.
    /// If `null`, the current state will continue unchanged next tic.
    scheduled_pause_state: ?PauseState = null,

    const Self = @This();

    /// On the next game tic, activate this thread and jump to the specified address.
    /// If the thread is currently inactive, then it will remain so for the rest of the current tic.
    pub fn scheduleJump(self: *Self, address: bytecode.Program.Address) void {
        self.scheduled_execution_state = .{ .active = address };
    }

    /// On the next game tic, deactivate this thread.
    /// If the thread is currently active, then it will remain so for the rest of the current tic.
    pub fn scheduleDeactivate(self: *Self) void {
        self.scheduled_execution_state = .inactive;
    }

    /// On the next game tic, resume running this thread.
    /// If the thread is currently paused, then it will remain so for the rest of the current tic.
    pub fn scheduleResume(self: *Self) void {
        self.scheduled_pause_state = .running;
    }

    /// On the next game tic, pause this thread.
    /// If the thread is currently active and running, then it will still run for the current tic if it hasn't already.
    pub fn schedulePause(self: *Self) void {
        self.scheduled_pause_state = .paused;
    }

    /// Apply any scheduled changes to the thread's execution and pause states.
    pub fn applyScheduledStates(self: *Self) void {
        if (self.scheduled_execution_state) |new_state| {
            self.execution_state = new_state;
            self.scheduled_execution_state = null;
        }

        if (self.scheduled_pause_state) |new_state| {
            self.pause_state = new_state;
            self.scheduled_pause_state = null;
        }
    }

    /// Reset the thread to its initial inactive state.
    /// Intended to be called when the virtual machine loads a new game part,
    /// to ensure thread state doesn't leak between parts.
    pub fn reset(self: *Self) void {
        self.execution_state = .inactive;
        self.pause_state = .running;
        self.scheduled_execution_state = null;
        self.scheduled_pause_state = null;
    }

    /// Activate the thread at the start of the program.
    /// Intended to be called on the primary thread when beginning a new game part.
    pub fn start(self: *Self) void {
        self.execution_state = .{ .active = 0 };
    }

    /// Execute the machine's current program on this thread, running until the thread yields
    /// or deactivates, or an error occurs, or the execution limit is exceeded.
    pub fn run(self: *Self, machine: *Machine, max_instructions: usize) !void {
        if (self.pause_state == .paused) return;

        // If this thread is active, resume executing the program from the previous address for this thread;
        // Otherwise, skip the thread.
        switch (self.execution_state) {
            .active => |address| try machine.program.jump(address),
            .inactive => return,
        }

        // Empty the stack before running each thread.
        machine.stack.clear();

        const result = try bytecode.executeProgram(&machine.program, machine, max_instructions);
        self.execution_state = switch (result) {
            // On yield, record the final position of the program counter so we can resume from there next tic.
            .yield => .{ .active = machine.program.counter },
            .deactivate => .inactive,
        };
    }
};

// -- Tests --

const testing = @import("utils").testing;

// - Schedule tests -

test "scheduleJump schedules activation with specified program counter for next tic" {
    var thread = Thread{};

    thread.scheduleJump(0xDEAD);

    try testing.expectEqual(.inactive, thread.execution_state);
    try testing.expectEqual(.{ .active = 0xDEAD }, thread.scheduled_execution_state);
}

test "scheduleDeactivate schedules deactivation for next tic" {
    var thread = Thread{ .execution_state = .{ .active = 0xDEAD } };

    thread.scheduleDeactivate();

    try testing.expectEqual(.{ .active = 0xDEAD }, thread.execution_state);
    try testing.expectEqual(.inactive, thread.scheduled_execution_state);
}

test "scheduleResume schedules resuming for next tic" {
    var thread = Thread{ .pause_state = .paused };

    thread.scheduleResume();

    try testing.expectEqual(.paused, thread.pause_state);
    try testing.expectEqual(.running, thread.scheduled_pause_state);
}

test "schedulePause schedules pausing for next tic" {
    var thread = Thread{};

    thread.schedulePause();

    try testing.expectEqual(.running, thread.pause_state);
    try testing.expectEqual(.paused, thread.scheduled_pause_state);
}

test "applyScheduledStates applies scheduled execution state" {
    var thread = Thread{};

    thread.scheduleJump(0xDEAD);
    try testing.expectEqual(.inactive, thread.execution_state);
    try testing.expectEqual(.{ .active = 0xDEAD }, thread.scheduled_execution_state);

    thread.applyScheduledStates();
    try testing.expectEqual(.{ .active = 0xDEAD }, thread.execution_state);
    try testing.expectEqual(null, thread.scheduled_execution_state);

    thread.scheduleDeactivate();
    try testing.expectEqual(.{ .active = 0xDEAD }, thread.execution_state);
    try testing.expectEqual(.inactive, thread.scheduled_execution_state);

    thread.applyScheduledStates();
    try testing.expectEqual(.inactive, thread.execution_state);
    try testing.expectEqual(null, thread.scheduled_execution_state);
}

test "applyScheduledStates applies scheduled pause state" {
    var thread = Thread{};

    try testing.expectEqual(.running, thread.pause_state);
    try testing.expectEqual(null, thread.scheduled_pause_state);

    thread.schedulePause();
    try testing.expectEqual(.running, thread.pause_state);
    try testing.expectEqual(.paused, thread.scheduled_pause_state);

    thread.applyScheduledStates();
    try testing.expectEqual(.paused, thread.pause_state);
    try testing.expectEqual(null, thread.scheduled_pause_state);

    thread.scheduleResume();
    try testing.expectEqual(.paused, thread.pause_state);
    try testing.expectEqual(.running, thread.scheduled_pause_state);

    thread.applyScheduledStates();
    try testing.expectEqual(.running, thread.pause_state);
    try testing.expectEqual(null, thread.scheduled_pause_state);
}

// - Run tests -

test "run stores program counter in thread state upon reaching yield instruction" {
    const program_data = bytecode.Instruction.Yield.Fixtures.valid;

    var machine = Machine.testInstance(.{ .program_data = &program_data });
    defer machine.deinit();

    const thread = &machine.threads[0];
    try thread.run(&machine, 10);
    try testing.expectEqual(.{ .active = 1 }, thread.execution_state);
}

test "run deactivates thread upon reaching kill instruction" {
    const program_data = bytecode.Instruction.Kill.Fixtures.valid;

    var machine = Machine.testInstance(.{ .program_data = &program_data });
    defer machine.deinit();

    const thread = &machine.threads[0];
    try thread.run(&machine, 10);
    try testing.expectEqual(.inactive, thread.execution_state);
}
