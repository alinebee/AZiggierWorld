//! This file defines a type for managing the state of the program execution stack.
//!
//! As an Another World program calls subroutines, the stack will be incremented
//! with the return address for that subroutine; as each subroutine returns,
//! the stack will be decremented and program execution will resume from the return address.
//!
//! In Another World's VM, the stack is thread-specific and will be cleared between threads.
//! The reference implementation supported a maximum stack depth of 64:
//! https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/vm.h#L81
//! However, it's not clear that the stack depth will ever exceed 1 in the original DOS bytecode
//! (i.e. the game may never use nested subroutines).

const anotherworld = @import("../lib/anotherworld.zig");
const static_limits = anotherworld.static_limits;

const Program = @import("program.zig").Program;

/// Represents the state of the program execution stack.
pub const Stack = struct {
    /// The addresses currently on the stack.
    return_addresses: [max_depth]Program.Address = undefined,
    /// The current depth on the stack, between 0 and 63.
    depth: usize = 0,

    const Self = @This();

    /// Add a new return address onto the stack.
    pub fn push(self: *Self, address: Program.Address) Error!void {
        if (self.depth >= self.return_addresses.len) {
            return error.StackOverflow;
        }
        self.return_addresses[self.depth] = address;
        self.depth += 1;
    }

    /// Decrement the stack and return the last return address that was on the stack.
    pub fn pop(self: *Self) Error!Program.Address {
        if (self.depth == 0) {
            return error.StackUnderflow;
        }
        self.depth -= 1;
        return self.return_addresses[self.depth];
    }

    /// Empty the stack.
    pub fn clear(self: *Self) void {
        self.depth = 0;
    }

    // - Exported constants -

    pub const max_depth = static_limits.max_stack_depth;

    pub const Error = error{
        /// Attempted to call into another subroutine when there were too many on the stack already.
        StackOverflow,
        /// Attempted to return when there were no more subroutines on the stack.
        /// This indicates a programmer error in the original bytecode.
        StackUnderflow,
    };
};

// -- Tests --

const testing = anotherworld.testing;

test "Pushing increments the stack" {
    var stack = Stack{};
    try testing.expectEqual(0, stack.depth);

    try stack.push(0xBEEF);
    try testing.expectEqual(1, stack.depth);
}

test "Popping decrements the stack and returns the last pushed address" {
    var stack = Stack{};
    try stack.push(0xDEAD);
    try stack.push(0xBEEF);
    try testing.expectEqual(2, stack.depth);

    try testing.expectEqual(0xBEEF, stack.pop());
    try testing.expectEqual(0xDEAD, stack.pop());
    try testing.expectEqual(0, stack.depth);
}

test "Clearing empties the stack" {
    var stack = Stack{};
    try stack.push(0x8BAD);
    try stack.push(0xF00D);
    try stack.push(0xDEAD);
    try stack.push(0xBEEF);
    try testing.expectEqual(4, stack.depth);

    stack.clear();
    try testing.expectEqual(0, stack.depth);
}

test "Popping an empty stack returns error.StackUnderflow" {
    var stack = Stack{};
    try testing.expectError(error.StackUnderflow, stack.pop());
}

test "Pushing onto a full stack returns error.StackOverflow" {
    var stack = Stack{};
    var remaining: usize = Stack.max_depth;
    while (remaining > 0) : (remaining -= 1) {
        try stack.push(0xBEEF);
    }

    try testing.expectError(error.StackOverflow, stack.push(0xDEAD));
}
