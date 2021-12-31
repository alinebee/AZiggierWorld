//! A mock implementation of a virtual machine host, intended for unit tests.

const Host = @import("../host.zig");

var test_host_implementation = Instance.init(null);
pub var test_host = test_host_implementation.host();

pub const Instance = struct {
    prepare_surface_error: ?Host.PrepareSurfaceError,
    surface: Host.Surface = undefined,
    call_counts: struct {
        prepareSurface: usize = 0,
        surfaceReady: usize = 0,
    } = .{},

    const Self = @This();

    /// Create a new host with a suitably-sized video surface to render into.
    pub fn init(prepare_surface_error: ?Host.PrepareSurfaceError) Self {
        return Instance{ .prepare_surface_error = prepare_surface_error };
    }

    pub fn host(self: *Self) Host.Interface {
        return Host.Interface.init(self, prepareSurface, surfaceReady);
    }

    fn prepareSurface(self: *Self) Host.PrepareSurfaceResult {
        self.call_counts.prepareSurface += 1;
        return self.prepare_surface_error orelse &self.surface;
    }

    fn surfaceReady(self: *Self, surface: *Host.Surface, _: Host.Milliseconds) void {
        self.call_counts.surfaceReady += 1;
        testing.expectEqual(&self.surface, surface) catch unreachable;
    }
};

// -- Tests --

const testing = @import("../../utils/testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(Instance);
}
