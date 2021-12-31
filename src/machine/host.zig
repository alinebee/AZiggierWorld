//! Provides a standard interface for an Another World virtual machine to communicate
//! with the host environment by sending video and audio output and polling for player input.

const std = @import("std");
const assert = std.debug.assert;

pub const Milliseconds = @import("video.zig").Milliseconds;

/// The destination buffer type used for rendering frame data from Another World's
/// 320x200 paletted framebuffers to the host screen.
pub const Surface = @import("../rendering/surface.zig").Default;

/// The possible errors returned from a call to `prepareSurface`.
/// Hosts must map any internal errors into one of these constants.
pub const PrepareSurfaceError = error{
    CannotCreateSurface,
};

/// The result returned from a call to `prepareSurface`.
pub const PrepareSurfaceResult = PrepareSurfaceError!*Surface;

/// An interface that the virtual machine uses to communicate with the host.
/// The host handles video and audio output from the virtual machine as well as input from the player.
pub const Interface = struct {
    implementation: *anyopaque,
    vtable: *const TypeErasedVTable,

    const TypeErasedVTable = struct {
        prepareSurface: fn (implementation: *anyopaque) PrepareSurfaceResult,
        surfaceReady: fn (implementation: *anyopaque, surface: *Surface, delay: Milliseconds) void,
    };

    const Self = @This();

    /// Create a new type-erased "fat pointer" that calls methods on the specified implementation.
    /// Intended to be called by implementations to create a host interface; should not be used directly.
    pub fn init(
        implementation_ptr: anytype,
        comptime prepareSurfaceFn: fn (self: @TypeOf(implementation_ptr)) PrepareSurfaceResult,
        comptime surfaceReadyFn: fn (self: @TypeOf(implementation_ptr), surface: *Surface, delay: Milliseconds) void,
    ) Self {
        const Implementation = @TypeOf(implementation_ptr);
        const ptr_info = @typeInfo(Implementation);

        assert(ptr_info == .Pointer); // Must be a pointer
        assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer

        const alignment = ptr_info.Pointer.alignment;

        const TypeUnerasedVTable = struct {
            fn prepareSurfaceImpl(type_erased_self: *anyopaque) PrepareSurfaceResult {
                const self = @ptrCast(Implementation, @alignCast(alignment, type_erased_self));
                return @call(.{ .modifier = .always_inline }, prepareSurfaceFn, .{self});
            }

            fn surfaceReadyImpl(type_erased_self: *anyopaque, surface: *Surface, delay: Milliseconds) void {
                const self = @ptrCast(Implementation, @alignCast(alignment, type_erased_self));
                return @call(.{ .modifier = .always_inline }, surfaceReadyFn, .{ self, surface, delay });
            }

            const vtable = TypeErasedVTable{
                .prepareSurface = prepareSurfaceImpl,
                .surfaceReady = surfaceReadyImpl,
            };
        };

        return .{
            .implementation = implementation_ptr,
            .vtable = &TypeUnerasedVTable.vtable,
        };
    }

    /// Called when the video subsystem wants to render a frame to the host screen.
    /// The implementation is expected to return a pointer to a one-dimensional buffer
    /// large enough to hold (virtual secreen width x height) 24-bit color values,
    /// or error.CannotCreateSurface on failure.
    ///
    /// The buffer's contents will be entirely replaced with frame pixels at some point
    /// between `prepareSurface` being called and `surfaceReady` being called.
    /// The host should not read or modify the returned buffer until `surfaceReady`
    /// has been called.
    pub fn prepareSurface(self: Self) PrepareSurfaceResult {
        return try self.vtable.prepareSurface(self.implementation);
    }

    /// Called when the video subsystem has finished filling a surface
    /// (previously provided by prepareSurface) with frame data, and is ready to display it.
    /// `delay` is the number of milliseconds that the host should continue displaying
    /// the *previous* frame before replacing it with this one.
    /// (The host may modify this delay to speed up or slow down gameplay.)
    pub fn surfaceReady(self: Self, surface: *Surface, delay: Milliseconds) void {
        self.vtable.surfaceReady(self.implementation, surface, delay);
    }
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(Interface);
}
