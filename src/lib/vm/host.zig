//! Provides a standard interface for an Another World virtual machine to communicate
//! with the host environment by sending it video and audio output.

const anotherworld = @import("../anotherworld.zig");

const std = @import("std");
const assert = std.debug.assert;

const Machine = @import("machine.zig").Machine;
const ResolvedBufferID = @import("video.zig").Video.ResolvedBufferID;
const Milliseconds = @import("video.zig").Video.Milliseconds;

/// An interface that the virtual machine uses to communicate with the host.
/// The host handles video and audio output from the virtual machine.
pub const Host = struct {
    implementation: *anyopaque,
    vtable: *const TypeErasedVTable,

    const TypeErasedVTable = struct {
        bufferReady: fn (implementation: *anyopaque, machine: *const Machine, buffer_id: ResolvedBufferID, delay: Milliseconds) void,
    };

    const Self = @This();

    /// Create a new type-erased "fat pointer" that calls methods on the specified implementation.
    /// Intended to be called by implementations to create a host interface; should not be used directly.
    pub fn init(
        implementation_ptr: anytype,
        comptime bufferReadyFn: fn (self: @TypeOf(implementation_ptr), machine: *const Machine, buffer_id: ResolvedBufferID, delay: Milliseconds) void,
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

            const vtable = TypeErasedVTable{
                .bufferReady = bufferReadyImpl,
            };
        };

        return .{
            .implementation = implementation_ptr,
            .vtable = &TypeUnerasedVTable.vtable,
        };
    }

    /// Called when the specified machine has finished filling the specified buffer
    /// with frame data and is ready to display it. The host can request the contents
    /// of the buffer to be rendered into a 24-bit surface using `machine.renderBufferToSurface(buffer_id, &surface).`
    ///
    /// `delay` is the number of milliseconds that the host should continue displaying
    /// the *previous* frame before replacing it with this one.
    /// (The host may modify this delay to speed up or slow down gameplay.)
    pub fn bufferReady(self: Self, machine: *const Machine, buffer_id: ResolvedBufferID, delay: Milliseconds) void {
        self.vtable.bufferReady(self.implementation, machine, buffer_id, delay);
    }
};

// -- Tests --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(Host);
}
