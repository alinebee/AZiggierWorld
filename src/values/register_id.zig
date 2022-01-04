/// A raw register identifier as represented in Another World's bytecode.
/// Guaranteed at compile-time to be valid, as the VM has exactly 256 registers.
pub const Raw = u8;

const Register = @import("register.zig");

// -- Known register ID constants and their initial values (where known) --

/// UNKNOWN: Set to 129 (0x81) at VM startup in reference implementation.
pub const virtual_machine_startup_UNKNOWN: Raw = 0x54;
pub const virtual_machine_startup_UNKNOWN_initial_value: Register.Unsigned = 0x81;

/// Seeded at VM startup from the current system time, for use in random calculations.
pub const random_seed: Raw = 0x3C;

/// The keycode of the last key that was pressed. Set when processing user input.
pub const last_keychar: Raw = 0xDA;

// These placeholder names are copypasta from the reference implementation:
// https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/vm.h#L30
pub const hero_pos_up_down: Raw = 0xE5;
pub const music_mark: Raw = 0xF4;
pub const scroll_y_position: Raw = 0xF9;
pub const hero_action: Raw = 0xFA;
pub const hero_pos_jump_down: Raw = 0xFB;
pub const hero_pos_left_right: Raw = 0xFC;
pub const hero_pos_mask: Raw = 0xFD;
pub const hero_action_pos_mask: Raw = 0xFE;

/// How long to leave the current frame on-screen before rendering the next frame.
/// Read when drawing a buffer to the screen.
pub const frame_duration: Raw = 0xFF;

/// UNKNOWN: Reset to 0 by render_video_buffer right before a new frame is rendered.
pub const render_video_buffer_UNKNOWN: Raw = 0xF7;

// -- Tests --

const static_limits = @import("../static_limits.zig");

test "Raw type matches range of legal register IDs" {
    try static_limits.validateTrustedType(Raw, static_limits.register_count);
}
