const fmt = @import("std").fmt;

/// A raw register identifier as represented in Another World's bytecode.
/// Guaranteed at compile-time to be valid, as the VM has exactly 256 registers.
pub const Raw = u8;

/// A non-exhaustive enumeration of known register IDs used in Another World's bytecode.
pub const Enum = enum(Raw) {
    /// UNKNOWN: Set to 129 (0x81) at VM startup in reference implementation.
    virtual_machine_startup_UNKNOWN = 0x54,

    /// The seed used for random calculations, set at VM startup.
    /// The reference implementation seeded this with the current system time.
    random_seed = 0x3C,

    /// The keycode of the last key that was pressed. Set when processing user input.
    last_keychar = 0xDA,

    // These placeholder names are copypasta from the reference implementation:
    // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/vm.h#L30
    hero_pos_up_down = 0xE5,
    music_mark = 0xF4,
    scroll_y_position = 0xF9,
    hero_action = 0xFA,
    hero_pos_jump_down = 0xFB,
    hero_pos_left_right = 0xFC,
    hero_pos_mask = 0xFD,
    hero_action_pos_mask = 0xFE,

    /// UNKNOWN: Reset to 0 by render_video_buffer right before a new frame is rendered.
    render_video_buffer_UNKNOWN = 0xF7,

    /// How long to leave the current frame on-screen before rendering the next frame.
    /// Read when drawing a buffer to the screen.
    frame_duration = 0xFF,

    // Make this a non-exhaustive enum: allows any arbitrary 8-bit integer to be safely cast to this enum type.
    _,
};

/// Parse an arbitrary 8-bit unsigned integer into a RegisterID enum.
/// This parsing is always successful, even if the integer does not match a known ID.
pub fn parse(raw: Raw) Enum {
    return @intToEnum(Enum, raw);
}

// -- Tests --

const static_limits = @import("../static_limits.zig");

test "Raw type matches range of legal register IDs" {
    try static_limits.validateTrustedType(Raw, static_limits.register_count);
}
