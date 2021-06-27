/// A raw register identifier as represented in Another World's bytecode.
pub const Raw = u8;

// -- Known register ID constants --

/// Set at VM start for use in random calculations.
pub const random_seed: Raw = 0x3C;

/// Read when copying a buffer to the screen.
pub const scroll_y_position: Raw = 0xF9;

// These placeholder names are copypasta from the reference implementation:
// https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/vm.h#L30
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
