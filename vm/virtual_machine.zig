const thread_count = @import("types/thread_id.zig").count;

const thread = @import("types/thread.zig");

pub const VirtualMachine = struct {
    /// The current state of the VM's 64 threads.
    threads: [thread_count]thread.Thread,

    pub fn init() VirtualMachine {
        var vm = VirtualMachine {
            .threads = [_]thread.Thread { thread.Thread { } } ** thread_count,
        };

        // Initialize the main thread (0) to begin execution at the start of the current program
        vm.threads[0].execution_state = thread.ExecutionState { .active = 0 };

        return vm;
    }
};
