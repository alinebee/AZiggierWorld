//! Provides a standard interface for an Another World virtual machine to communicate
//! with the host environment, by sending video and audio output to callback functions
//! defined by the host.
//!
//! Expected usage:
//!
//! const MyHost = struct {
//!   fn host(self: *MyHost) Host {
//!     // All callbacks are optional: only include the ones you care about receiving.
//!     return Host.init(self, .{ .bufferReady = bufferReady, .bufferChanged = bufferChanged });
//!   }
//!
//!   fn bufferReady(self: *MyHost, machine: *const Machine, buffer_id: ResolvedBufferID, delay: Milliseconds) void {
//!     machine.renderBufferToSurface(buffer_id, &self.surface);
//!   }
//!
//!   fn bufferChanged(self: *MyHost, machine: *const Machine, buffer_id: ResolvedBufferID) {
//!     self.debugLogDrawCall(buffer_id);
//!   }
//! }
//!

const anotherworld = @import("../anotherworld.zig");
const meta = @import("utils").meta;

const std = @import("std");

const Machine = @import("machine.zig").Machine;
const ResolvedBufferID = @import("video.zig").Video.ResolvedBufferID;
const Milliseconds = @import("video.zig").Video.Milliseconds;

fn BufferReadySig(comptime State: type) type {
    return fn (state: State, machine: *const Machine, buffer_id: ResolvedBufferID, delay: Milliseconds) void;
}

fn BufferChangedSig(comptime State: type) type {
    return fn (state: State, machine: *const Machine, buffer_id: ResolvedBufferID) void;
}

fn Functions(comptime State: type) type {
    return struct {
        bufferReady: ?BufferReadySig(State) = null,
        bufferChanged: ?BufferChangedSig(State) = null,
    };
}

const TypeErasedVTable = struct {
    bufferReady: BufferReadySig(*anyopaque),
    bufferChanged: BufferChangedSig(*anyopaque),
};

/// An interface that the virtual machine uses to communicate with the host.
/// The host handles video and audio output from the virtual machine.
pub const Host = struct {
    state: *anyopaque,
    vtable: *const TypeErasedVTable,

    const Self = @This();

    /// Create a new type-erased "fat pointer" whose functions call host-provided callbacks and pass them
    /// a state pointer provided by the host.
    /// Intended to be called by implementations to create a host interface pointing to their own functions.
    pub fn init(state: anytype, comptime functions: Functions(@TypeOf(state))) Self {
        const State = @TypeOf(state);

        const vtable = comptime meta.generateVTable(TypeErasedVTable, struct {
            pub fn bufferReady(type_erased_state: *anyopaque, machine: *const Machine, buffer_id: ResolvedBufferID, delay: Milliseconds) void {
                if (functions.bufferReady) |function| {
                    return meta.unerasedCall(State, function, type_erased_state, .{ machine, buffer_id, delay });
                }
            }

            pub fn bufferChanged(type_erased_state: *anyopaque, machine: *const Machine, buffer_id: ResolvedBufferID) void {
                if (functions.bufferChanged) |function| {
                    return meta.unerasedCall(State, function, type_erased_state, .{ machine, buffer_id });
                }
            }
        });

        return .{ .state = state, .vtable = &vtable };
    }

    /// Called when the specified machine has finished filling the specified video buffer
    /// with frame data and is ready to display it. The host can request the contents
    /// of the buffer to be rendered into a 24-bit surface using
    /// `machine.renderBufferToSurface(buffer_id, &surface).`
    ///
    /// `delay` is the number of milliseconds that the host should continue displaying
    /// the *previous* frame before replacing it with this one.
    /// (The host may modify this delay to speed up or slow down gameplay.)
    pub fn bufferReady(self: Self, machine: *const Machine, buffer_id: ResolvedBufferID, delay: Milliseconds) void {
        self.vtable.bufferReady(self.state, machine, buffer_id, delay);
    }

    /// Called each time the specified machine draws pixel data into a video buffer.
    /// The host can request the contents of the buffer to be rendered into a 24-bit surface
    /// using `machine.renderBufferToSurface(buffer_id, &surface).`
    pub fn bufferChanged(self: Self, machine: *const Machine, buffer_id: ResolvedBufferID) void {
        self.vtable.bufferChanged(self.state, machine, buffer_id);
    }
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(Host);
}

test "Host calls callback implementations" {
    const expected_buffer_id: ResolvedBufferID = 0;
    const expected_delay: Milliseconds = 0;

    const Implementation = struct {
        call_counts: struct {
            bufferReady: usize = 0,
            bufferChanged: usize = 0,
        } = .{},

        const Self = @This();

        fn bufferReady(self: *Self, _: *const Machine, buffer_id: ResolvedBufferID, delay: Milliseconds) void {
            self.call_counts.bufferReady += 1;
            testing.expectEqual(expected_buffer_id, buffer_id) catch unreachable;
            testing.expectEqual(expected_delay, delay) catch unreachable;
        }

        fn bufferChanged(self: *Self, _: *const Machine, buffer_id: ResolvedBufferID) void {
            self.call_counts.bufferChanged += 1;
            testing.expectEqual(expected_buffer_id, buffer_id) catch unreachable;
        }

        fn host(self: *Self) Host {
            return Host.init(self, .{
                .bufferReady = bufferReady,
                .bufferChanged = bufferChanged,
            });
        }
    };

    var implementation = Implementation{};
    const host = implementation.host();

    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    host.bufferReady(&machine, expected_buffer_id, expected_delay);
    try testing.expectEqual(1, implementation.call_counts.bufferReady);

    host.bufferChanged(&machine, expected_buffer_id);
    try testing.expectEqual(1, implementation.call_counts.bufferChanged);
}
