const fmt = @import("std").fmt;

const _Raw = u8;

/// A non-exhaustive enumeration of known register IDs used in Another World's bytecode.
pub const RegisterID = enum(_Raw) {
    /// UNKNOWN: Set to 129 (0x81) at VM startup in reference implementation:
    /// https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/vm.cpp#L37
    virtual_machine_startup_UNKNOWN = 0x54,

    /// Set by the reference implementation to bypass copy protection:
    /// https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/vm.cpp#L40-L45
    /// The first gameplay sequence will freeze if these are not set to the correct values.
    /// These may be incomplete, because the 3rd gameplay sequence will freeze even if these are all set.
    copy_protection_bypass_1 = 0xBC,
    copy_protection_bypass_2 = 0xC6,
    copy_protection_bypass_3 = 0xDC,
    copy_protection_bypass_4 = 0xF2,

    /// The seed used for random calculations, set at VM startup.
    /// The reference implementation seeded this with the current system time.
    random_seed = 0x3C,

    /// The ASCII character of the last alphanumeric key that was pressed.
    /// Used for keyboard entry in the password entry screen.
    /// See user_input.zig for possible values.
    last_pressed_character = 0xDA,

    /// The state of the user's up/down input. See user_input.zig for possible values.
    up_down_input = 0xE5,

    /// Whether the action button is held down. See user_input.zig for possible values.
    action_input = 0xFA,

    /// In the reference implementation, this is always set to the same value as `up_down_input`.
    up_down_input_2 = 0xFB,

    /// The state of the user's left/right input. See user_input.zig for possible values.
    left_right_input = 0xFC,

    /// A combined bitmask of the state of the user's movement inputs (up, down, left, right).
    /// See user_input.zig for possible values.
    movement_inputs = 0xFD,

    /// A combined bitmask of the state of the user's movement inputs (up, down, left, right)
    /// and the state of the action button.
    /// See user_input.zig for possible values.
    all_inputs = 0xFE,

    /// How much to vertically offset the scene background, on screens that scroll vertically.
    /// Read by the `CopyVideoBuffer` instruction.
    scroll_y_position = 0xF9,

    /// Copypasta from reference implementation:
    // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/vm.h#L30
    music_mark = 0xF4,

    /// UNKNOWN: Reset to 0 by render_video_buffer right before a new frame is rendered.
    render_video_buffer_UNKNOWN = 0xF7,

    /// How long to leave the current frame on-screen before rendering the next frame.
    /// Read when drawing a buffer to the screen.
    frame_duration = 0xFF,

    // Make this a non-exhaustive enum: allows any arbitrary 8-bit integer to be safely cast to this enum type.
    _,

    /// A raw register identifier as represented in Another World's bytecode.
    /// Guaranteed at compile-time to be valid, as the VM has exactly 256 registers.
    pub const Raw = _Raw;

    /// Cast an arbitrary 8-bit unsigned integer into a RegisterID enum.
    pub fn cast(raw: Raw) RegisterID {
        return @intToEnum(RegisterID, raw);
    }

    /// Returns the RegisterID converted to an array index.
    pub fn index(id: RegisterID) usize {
        return @enumToInt(id);
    }

    /// Returns the RegisterID converted to its raw bytecode representation.
    pub fn encode(id: RegisterID) Raw {
        return @enumToInt(id);
    }
};

// -- Tests --

const static_limits = @import("../static_limits.zig");

test "Raw type matches range of legal register IDs" {
    try static_limits.validateTrustedType(_Raw, static_limits.register_count);
}
