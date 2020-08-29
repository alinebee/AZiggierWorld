const Thread = @import("types/thread.zig").Thread;

pub const max_threads = 64;

pub const VirtualMachine = struct {
    /// The current state of the VM's 64 threads.
    threads: [max_threads]Thread,

    pub fn init() VirtualMachine {
        var vm = VirtualMachine {
            .threads = [_]Thread { .{} } ** max_threads,
        };

        // Initialize the main thread (0) to begin execution at the start of the current program
        vm.threads[0].execution_state = .{ .active = 0 };

        return vm;
    }
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "init creates new virtual machine with expected state" {
    const vm = VirtualMachine.init();

    testing.expectEqual(.{ .active = 0 }, vm.threads[0].execution_state);
}
