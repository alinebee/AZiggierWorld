//! Provides a standard interface for an Another World virtual machine to communicate
//! with the host environment by sending it video and audio output.

const std = @import("std");
const assert = std.debug.assert;

const BufferID = @import("../values/buffer_id.zig");
const Video = @import("video.zig");
pub const Milliseconds = Video.Milliseconds;

/// An interface that the virtual machine uses to communicate with the host.
/// The host handles video and audio output from the virtual machine.
pub const Interface = struct {
    implementation: *anyopaque,
    vtable: *const TypeErasedVTable,

    const TypeErasedVTable = struct {
        bufferReady: fn (implementation: *anyopaque, video: *const Video.Instance, buffer_id: BufferID.Specific, delay: Milliseconds) void,
    };

    const Self = @This();

    /// Create a new type-erased "fat pointer" that calls methods on the specified implementation.
    /// Intended to be called by implementations to create a host interface; should not be used directly.
    pub fn init(
        implementation_ptr: anytype,
        comptime bufferReadyFn: fn (self: @TypeOf(implementation_ptr), video: *const Video.Instance, buffer_id: BufferID.Specific, delay: Milliseconds) void,
    ) Self {
        const Implementation = @TypeOf(implementation_ptr);
        const ptr_info = @typeInfo(Implementation);

        assert(ptr_info == .Pointer); // Must be a pointer
        assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer

        const alignment = ptr_info.Pointer.alignment;

        const TypeUnerasedVTable = struct {
            fn bufferReadyImpl(type_erased_self: *anyopaque, video: *const Video.Instance, buffer_id: BufferID.Specific, delay: Milliseconds) void {
                const self = @ptrCast(Implementation, @alignCast(alignment, type_erased_self));
                return @call(.{ .modifier = .always_inline }, bufferReadyFn, .{ self, video, buffer_id, delay });
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

    /// Called when the specified video subsystem has finished filling the specified buffer
    /// with frame data and is ready to display it. The host can request the contents
    /// of the buffer to be rendered into a 24-bit surface using `video.renderIntoSurface(buffer_id, &surface).`
    ///
    /// `delay` is the number of milliseconds that the host should continue displaying
    /// the *previous* frame before replacing it with this one.
    /// (The host may modify this delay to speed up or slow down gameplay.)
    pub fn bufferReady(self: Self, video: *const Video.Instance, buffer_id: BufferID.Specific, delay: Milliseconds) void {
        self.vtable.bufferReady(self.implementation, video, buffer_id, delay);
    }
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(Interface);
}
