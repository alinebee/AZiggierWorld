//! A mock implementation of a virtual machine host, intended for unit tests.
//! Records the number of times each host method was called, and allows a test
//! to perform arbitrary assertions in the body of each host method.

const Host = @import("../host.zig");
const Video = @import("../video.zig");
const BufferID = @import("../../values/buffer_id.zig");

var test_host_implementation = new(DefaultImplementation);
pub var test_host = test_host_implementation.host();

/// Returns a fake instance that defers to the specified struct to implement its functions.
pub fn new(comptime Implementation: type) Instance(Implementation) {
    return .{};
}

pub fn Instance(comptime Implementation: type) type {
    return struct {
        call_counts: struct {
            bufferReady: usize = 0,
        } = .{},

        const Self = @This();

        pub fn host(self: *Self) Host.Interface {
            return Host.Interface.init(self, bufferReady);
        }

        fn bufferReady(self: *Self, video: *const Video.Instance, buffer_id: BufferID.Specific, delay: Host.Milliseconds) void {
            self.call_counts.bufferReady += 1;
            Implementation.bufferReady(video, buffer_id, delay);
        }
    };
}

/// A default implementation for the mock host that does nothing in any method.
pub const DefaultImplementation = struct {
    pub fn bufferReady(_: *const Video.Instance, _: BufferID.Specific, _: Host.Milliseconds) void {}
};

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(Instance(DefaultImplementation));
}
