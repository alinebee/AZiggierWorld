//! A mock implementation of a virtual machine host, intended for unit tests.
//! Records the number of times each host method was called, and allows a test
//! to perform arbitrary assertions in the body of each host method.

const Host = @import("../host.zig").Host;
const Machine = @import("../machine.zig");
const BufferID = @import("../../values/buffer_id.zig");

// - Exported constants -

const DefaultImplementation = struct {
    pub fn bufferReady(_: *const Machine.Instance, _: BufferID.Specific, _: Host.Milliseconds) void {}
};

var test_host_implementation = MockHost(DefaultImplementation){};

/// A default host implementation that responds to all host methods but does nothing:
/// intended to be used as a mock in tests that need a real instance but do not test the host functionality.
pub const test_host = test_host_implementation.host();

pub fn MockHost(comptime Implementation: type) type {
    return struct {
        call_counts: struct {
            bufferReady: usize = 0,
        } = .{},

        const Self = @This();

        pub fn host(self: *Self) Host {
            return Host.init(self, bufferReady);
        }

        fn bufferReady(self: *Self, machine: *const Machine.Instance, buffer_id: BufferID.Specific, delay: Host.Milliseconds) void {
            self.call_counts.bufferReady += 1;
            Implementation.bufferReady(machine, buffer_id, delay);
        }
    };
}

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(MockHost(DefaultImplementation));
}
