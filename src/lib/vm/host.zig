//! Provides a standard interface for an Another World virtual machine to communicate
//! with the host environment by sending it video and audio output.

const anotherworld = @import("../anotherworld.zig");

const std = @import("std");
const assert = std.debug.assert;

const Machine = @import("machine.zig").Machine;
const ResolvedBufferID = @import("video.zig").Video.ResolvedBufferID;
const Milliseconds = @import("video.zig").Video.Milliseconds;

fn bufferReadySig(comptime implementation_type: type) type {
    return fn (implementation: implementation_type, machine: *const Machine, buffer_id: ResolvedBufferID, delay: Milliseconds) void;
}

fn bufferChangedSig(comptime implementation_type: type) type {
    return fn (implementation: implementation_type, machine: *const Machine, buffer_id: ResolvedBufferID) void;
}

/// An interface that the virtual machine uses to communicate with the host.
/// The host handles video and audio output from the virtual machine.
pub const Host = struct {
    implementation: *anyopaque,
    vtable: *const TypeErasedVTable,

    const TypeErasedVTable = struct {
        bufferReady: bufferReadySig(*anyopaque),
        bufferChanged: bufferChangedSig(*anyopaque),
    };

    const Self = @This();

    /// Create a new type-erased "fat pointer" that calls methods on the specified implementation.
    /// Intended to be called by implementations to create a host interface; should not be used directly.
    pub fn init(
        implementation_ptr: anytype,
        comptime bufferReadyFn: bufferReadySig(@TypeOf(implementation_ptr)),
        comptime bufferChangedFn: ?bufferChangedSig(@TypeOf(implementation_ptr)),
    ) Self {
        const Implementation = @TypeOf(implementation_ptr);
        const ptr_info = @typeInfo(Implementation);

        assert(ptr_info == .Pointer); // Must be a pointer
        assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer

        const alignment = ptr_info.Pointer.alignment;

        const TypeUnerasedVTable = struct {
            fn bufferReadyImpl(type_erased_self: *anyopaque, machine: *const Machine, buffer_id: ResolvedBufferID, delay: Milliseconds) void {
                const self = @ptrCast(Implementation, @alignCast(alignment, type_erased_self));
                return @call(.{ .modifier = .always_inline }, bufferReadyFn, .{ self, machine, buffer_id, delay });
            }

            fn bufferChangedImpl(type_erased_self: *anyopaque, machine: *const Machine, buffer_id: ResolvedBufferID) void {
                if (bufferChangedFn) |impl| {
                    const self = @ptrCast(Implementation, @alignCast(alignment, type_erased_self));
                    return @call(.{ .modifier = .always_inline }, impl, .{ self, machine, buffer_id });
                }
            }

            const vtable = TypeErasedVTable{
                .bufferReady = bufferReadyImpl,
                .bufferChanged = bufferChangedImpl,
            };
        };

        return .{
            .implementation = implementation_ptr,
            .vtable = &TypeUnerasedVTable.vtable,
        };
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
        self.vtable.bufferReady(self.implementation, machine, buffer_id, delay);
    }

    /// Called each time the specified machine draws pixel data into a video buffer.
    /// The host can request the contents of the buffer to be rendered into a 24-bit surface
    /// using `machine.renderBufferToSurface(buffer_id, &surface).`
    pub fn bufferChanged(self: Self, machine: *const Machine, buffer_id: ResolvedBufferID) void {
        self.vtable.bufferChanged(self.implementation, machine, buffer_id);
    }
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(Host);
}
