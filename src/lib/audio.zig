//! This namespace will eventually define the audio subsystem responsible for sound and music playback.

pub const Delay = u16;
pub const Offset = u8;
pub const Volume = u8;
pub const Frequency = u8;

pub const SoundResource = @import("audio/sound_resource.zig");
pub const MusicResource = @import("audio/music_resource.zig");
