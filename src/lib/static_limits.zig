//! This file documents constants for the static limits used in the Another World engine.
//! Their minimum values are based on the requirements of the DOS release of Another World.

// -- Constants --

/// The number of threads used in the VM.
/// Threads are addressed in bytecode instructions using an unsigned 8-bit integer,
/// so this value must fit within a u8. Thread IDs are also bounds-checked by casting them
/// to a trusted u6 integer type: changing this value will require defining a new trusted type.
/// See thread_id.zig.
///
/// The DOS version of Another World addressed 64 threads.
pub const thread_count = 64;

/// The number of registers used in the VM.
/// Registers are addressed in bytecode instructions using an unsigned 8-bit integer,
/// so this value must fit within a u8. Register IDs are also bounds-checked by casting
/// them to a trusted u8 integer type: changing this value will require defining a new trusted type.
/// See register_id.zig.
///
/// The DOS version of Another World addressed 256 threads.
pub const register_count = 256;

/// The number of addressable video buffers.
/// Buffers are addressed in bytecode instructions using 6 bits of an unsigned 8-bit integer,
/// so this value must fit within a u6. Buffer IDs are also bounds-checked by casting them
/// to a trusted u2 integer type: changing this value will require defining a new trusted type.
/// See buffer_id.zig.
///
/// The DOS version of Another World uses 4 buffers.
pub const buffer_count = 4;

/// The number of addressable sound channels.
/// Channels are addressed in bytecode instructions using an unsigned 8-bit integer,
/// so this value must fit within a u8. Channel IDs are also bounds-checked by casting them
/// to a trusted u2 integer type: changing this value will require defining a new trusted type.
/// See channel.zig.
///
/// The DOS version of Another World uses 4 channels.
pub const channel_count = 4;

/// The number of addressable palettes.
/// Palettes are addressed in bytecode instructions using an unsigned 8-bit integer,
/// so this value must fit within a u8. Palette IDs are also bounds-checked by casting them
/// to a trusted u5 integer type: changing this value will require defining a new trusted type.
/// See palette_id.zig.
pub const palette_count = 32;

/// The number of addressable colors.
/// Colors are addressed in bytecode instructions using 4 bits of an unsigned 8-bit integer,
/// so this value must fit within a u4. Color IDs are also bounds-checked by casting them
/// to a trusted u4 integer type: changing this value will require defining a new trusted type.
/// See color_id.zig.
///
/// The DOS version of Another World uses 16 colors.
pub const color_count = 16;

/// The width in virtual screen pixels of the video buffer.
/// The DOS version of Another World stored bitmap resources as 320x200 images:
/// changing this value will require changing how bitmap resources are loaded into video buffers.
/// See video_buffer.zig and planar_bitmap.zig.
pub const virtual_screen_width = 320;

/// The height in virtual screen pixels of the video buffer.
/// The DOS version of Another World stored bitmap resources as 320x200 images:
/// changing this value will require changing how bitmap resources are loaded into video buffers.
/// See video_buffer.zig and planar_bitmap.zig.
pub const virtual_screen_height = 200;

/// The maximum size in bytes of an Another World game program.
pub const max_program_size = 65_536;

/// The maximum number of subroutines that can be on the stack.
/// Can be safely modified without changing types.
///
/// The DOS version of Another World capped the stack at 64 entries.
pub const max_stack_depth = 64;

/// The maximum number of instructions that a program can execute before
/// it must yield or deactivate the current thread.
/// If a program exceeds this, it likely indicates an infinite loop.
pub const max_instructions_per_tic = 10_000;

/// The maximum number of resource descriptors that will be parsed from the MEMLIST.BIN file
/// in an Another World game directory.
/// Determines the size of arrays that hold descriptors and memory state for resources.
///
/// Resources are addressed in bytecode instructions using an unsigned 16-bit integer,
/// so this value must fit within a u16. It must also be lower than 16000 (0x3E80),
/// to avoid overlapping with game part IDs which occupy the same address space.
/// See resource_id.zig and game_part.zig.
///
/// The DOS version of Another World has 146 resources.
pub const max_resource_descriptors = 150;

/// DOS 8.3 filenames require a maximum of 12 characters to represent.
pub const max_filename_length = 12;

/// The maximum number of vertices allowed in a single polygon.
/// Determines the size of the array of vertices within a polygon instance.
/// Can be safely modified without changing types.
///
/// The DOS version of Another World has no polygons greater than 40 vertices.
pub const max_polygon_vertices = 50;

/// The number of precomputed vertical slope values used in polygon drawing.
/// This defines the maximum vertical distance allowed between two adjacent polygon vertices.
/// Vertex distances are bounds-checked using a u10 integer type: changing this value
/// will require redefining that type. See video_buffer.zig.
///
/// The DOS version of Another World precomputed 1024 slope values.
pub const precomputed_slope_count = 1024;

// -- Helper functions --

const math = @import("std").math;

/// Several parts of the VM implementation use arbitrary-sized integer types to bounds-check
/// a runtime value (e.g. a thread ID) against a set of known legal values (e.g. the range
/// of addressible threads) based on a static limit (e.g. the total thread count).
/// This method validates that an unsigned integer type exactly matches its legal range of values.
pub fn validateTrustedType(comptime T: type, comptime limit: usize) !void {
    if (math.minInt(T) != 0) return error.MismatchedTrustedType;
    if (math.maxInt(T) != limit - 1) return error.MismatchedTrustedType;
}

const Error = error{
    /// A trusted type was the wrong size for its limit constant.
    MismatchedTrustedType,
};

// -- Tests --

const anotherworld = @import("anotherworld.zig");
const testing = @import("utils").testing;

test "validateTrustedType does not assert if trusted type matches limit" {
    const Trusted = u8;
    try validateTrustedType(Trusted, 256);
}

test "validateTrustedType asserts if trusted type is too small for limit" {
    const Trusted = u4;
    try testing.expectError(error.MismatchedTrustedType, validateTrustedType(Trusted, 256));
}

test "validateTrustedType asserts if trusted type is too large for limit" {
    const Trusted = u16;
    try testing.expectError(error.MismatchedTrustedType, validateTrustedType(Trusted, 256));
}
