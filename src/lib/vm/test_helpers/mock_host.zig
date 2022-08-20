//! A mock implementation of a virtual machine host, intended for unit tests.
//! Records the number of times each host method was called, and allows a test
//! to perform arbitrary assertions in the body of each host method.

const anotherworld = @import("../../anotherworld.zig");

const Host = @import("../host.zig").Host;
const Machine = @import("../machine.zig").Machine;
const ResolvedBufferID = @import("../video.zig").Video.ResolvedBufferID;
const Milliseconds = @import("../video.zig").Video.Milliseconds;

// - Exported constants -

const DefaultImplementation = struct {
    pub fn bufferReady(_: *const Machine, _: ResolvedBufferID, _: Milliseconds) void {}
    pub fn bufferChanged(_: *const Machine, _: ResolvedBufferID) void {}
};

var test_host_implementation = MockHost(DefaultImplementation){};

/// A default host implementation that responds to all host methods but does nothing:
/// intended to be used as a mock in tests that need a real instance but do not test the host functionality.
pub const test_host = test_host_implementation.host();

pub fn mockHost(comptime Implementation: type) MockHost(Implementation) {
    return MockHost(Implementation){};
}

pub fn MockHost(comptime Implementation: type) type {
    return struct {
        call_counts: struct {
            bufferReady: usize = 0,
            bufferChanged: usize = 0,
        } = .{},

        const Self = @This();

        pub fn host(self: *Self) Host {
            return Host.init(self, bufferReady, bufferChanged);
        }

        fn bufferReady(self: *Self, machine: *const Machine, buffer_id: ResolvedBufferID, delay: Milliseconds) void {
            self.call_counts.bufferReady += 1;
            Implementation.bufferReady(machine, buffer_id, delay);
        }

        fn bufferChanged(self: *Self, machine: *const Machine, buffer_id: ResolvedBufferID) void {
            self.call_counts.bufferChanged += 1;
            Implementation.bufferChanged(machine, buffer_id);
        }
    };
}

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(MockHost(DefaultImplementation));
}
