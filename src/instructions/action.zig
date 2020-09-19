/// Returned from an instruction's execute function to decide what the thread should do after executing.
pub const Enum = enum {
    /// The current thread should continue executing after this instruction.
    /// The default behaviour for almost all instructions.
    Continue,

    /// The current thread should yield to the next thread and resume from the current point
    /// in the program on its next cycle.
    YieldToNextThread,

    /// The current thread should deactivate itself and yield to the next thread.
    DeactivateThread,
};
