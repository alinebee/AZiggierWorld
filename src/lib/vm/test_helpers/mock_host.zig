//! A mock implementation of a virtual machine host, intended for unit tests.
//! Records the number of times each host method was called, and allows a test
//! to perform arbitrary assertions in the body of each host method.

const anotherworld = @import("../../anotherworld.zig");
const vm = anotherworld.vm;

// - Exported constants -

const DefaultImplementation = struct {
    pub fn videoFrameReady(_: *const vm.Machine, _: vm.ResolvedBufferID, _: vm.Milliseconds) void {}
    pub fn videoBufferChanged(_: *const vm.Machine, _: vm.ResolvedBufferID) void {}
    pub fn audioReady(_: *const vm.Machine, _: vm.AudioBuffer) void {}
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
            videoFrameReady: usize = 0,
            videoBufferChanged: usize = 0,
            audioReady: usize = 0,
        } = .{},

        const Self = @This();

        pub fn host(self: *Self) vm.Host {
            return vm.Host.init(self, .{
                .videoFrameReady = videoFrameReady,
                .videoBufferChanged = videoBufferChanged,
                .audioReady = audioReady,
            });
        }

        fn videoFrameReady(self: *Self, machine: *const vm.Machine, buffer_id: vm.ResolvedBufferID, delay: vm.Milliseconds) void {
            self.call_counts.videoFrameReady += 1;
            Implementation.videoFrameReady(machine, buffer_id, delay);
        }

        fn videoBufferChanged(self: *Self, machine: *const vm.Machine, buffer_id: vm.ResolvedBufferID) void {
            self.call_counts.videoBufferChanged += 1;
            Implementation.videoBufferChanged(machine, buffer_id);
        }

        fn audioReady(self: *Self, machine: *const vm.Machine, buffer: vm.AudioBuffer) void {
            self.call_counts.audioReady += 1;
            Implementation.audioReady(machine, buffer);
        }
    };
}

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(MockHost(DefaultImplementation));
}
