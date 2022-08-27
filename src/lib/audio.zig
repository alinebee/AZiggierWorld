//! This namespace will eventually define the audio subsystem responsible for sound and music playback.

pub const Delay = u16;
pub const Offset = u8;
pub const Volume = u8;
pub const Frequency = u8;

pub const SoundEffect = @import("audio/sound_effect.zig").SoundEffect;
pub const MusicResource = @import("audio/music_resource.zig").MusicResource;
