/// The possible ways that program execution can legally end.
/// Returned from a call to `executeProgram` to indicate the condition
/// that ended execution and inform the current thread what to do next.
/// Consumed by `Thread` to control the lifecycle of the thread.
/// Can be returned from an individual instruction's `execute` function
/// to terminate program execution after that instruction.
pub const Enum = enum {
    /// The current thread should pause execution at the current program counter
    /// and pass execution to the next thread.
    yield,
    /// The current thread should deactivate and pass execution to the next thread.
    deactivate,
};
