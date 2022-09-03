//! This namespace will eventually define the audio subsystem responsible for sound and music playback.

/// The tempo at which to play a music track, measured in ticks of the Amiga's CIA timer.
pub const Tempo = u16;

/// The frequency at which to play the sound effect in a music track,
/// measured in ticks of the Amiga's audio clock.
pub const Period = u16;

/// The index into a music track's sequence of patterns at which to start playing.
// TODO: restrict to 0-max_pattern_sequence_length-1
pub const Offset = u8;

/// The volume at which to play a sound effect or note in a music track.
// TODO: restrict to 0-max_volume
pub const Volume = u8;

pub const FrequencyID = @import("audio/frequency_id.zig").FrequencyID;
pub const SoundResource = @import("audio/sound_resource.zig").SoundResource;
pub const MusicResource = @import("audio/music_resource.zig").MusicResource;
