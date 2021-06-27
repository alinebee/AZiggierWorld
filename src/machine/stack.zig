const Address = @import("../values/address.zig");

/// The maximum number of subroutines that can be on the stack.
pub const max_depth = 64;

/// Represents the program execution stack.
///
/// As the program calls subroutines, the stack will be incremented with the return address
/// for that subroutine; as each subroutine returns, the stack will be decremented
/// and program execution will resume from that address.
///
/// In Another World's VM, the stack is thread-specific and will be cleared between threads.
pub const Instance = struct {
    /// The addresses currently on the stack.
    return_addresses: [max_depth]Address.Native = [_]Address.Native{0} ** max_depth,
    depth: usize = 0,

    pub fn push(self: *Instance, address: Address.Native) Error!void {
        if (self.depth >= self.return_addresses.len) {
            return error.StackOverflow;
        }
        self.return_addresses[self.depth] = address;
        self.depth += 1;
    }

    pub fn pop(self: *Instance) Error!Address.Native {
        if (self.depth == 0) {
            return error.StackUnderflow;
        }
        self.depth -= 1;
        return self.return_addresses[self.depth];
    }

    pub fn clear(self: *Instance) void {
        self.depth = 0;
    }
};

pub const Error = error{
    /// Attempted to call into another subroutine when there were too many on the stack already.
    StackOverflow,
    /// Attempted to return when there were no more subroutines on the stack.
    /// This indicates a programmer error in the original bytecode.
    StackUnderflow,
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "Pushing increments the stack" {
    var stack = Instance{};
    try testing.expectEqual(0, stack.depth);

    try stack.push(0xBEEF);
    try testing.expectEqual(1, stack.depth);
}

test "Popping decrements the stack and returns the last pushed address" {
    var stack = Instance{};
    try stack.push(0xDEAD);
    try stack.push(0xBEEF);
    try testing.expectEqual(2, stack.depth);

    try testing.expectEqual(0xBEEF, stack.pop());
    try testing.expectEqual(0xDEAD, stack.pop());
    try testing.expectEqual(0, stack.depth);
}

test "Clearing empties the stack" {
    var stack = Instance{};
    try stack.push(0x8BAD);
    try stack.push(0xF00D);
    try stack.push(0xDEAD);
    try stack.push(0xBEEF);
    try testing.expectEqual(4, stack.depth);

    stack.clear();
    try testing.expectEqual(0, stack.depth);
}

test "Popping an empty stack returns error.StackUnderflow" {
    var stack = Instance{};
    try testing.expectError(error.StackUnderflow, stack.pop());
}

test "Pushing onto a full stack returns error.StackOverflow" {
    var stack = Instance{};
    var remaining: usize = max_depth;
    while (remaining > 0) : (remaining -= 1) {
        try stack.push(0xBEEF);
    }

    try testing.expectError(error.StackOverflow, stack.push(0xDEAD));
}
