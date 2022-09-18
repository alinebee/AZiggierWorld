const std = @import("std");
const anotherworld = @import("anotherworld.zig");
const audio = anotherworld.audio;
const vm = anotherworld.vm;

/// A delay in milliseconds.
pub const Milliseconds = usize;

/// A frequency in Hz.
pub const Hz = usize;

/// Computes video and audio timings relative to a PAL or NTSC Amiga 1000/2000/500:
/// the machine for which Another World's data files and timings were originally defined.
pub const TimingMode = enum {
    pal,
    ntsc,

    /// The game files of Another World's DOS port appear to use PAL timings.
    pub const default = TimingMode.pal;

    /// Returns the frame rate in Hz (Frames Per Second) at which the Amiga ran in this timing mode.
    pub fn frameRate(self: TimingMode) Hz {
        return switch (self) {
            .pal => 50,
            .ntsc => 60,
        };
    }

    /// Returns the rate in Hz of the Amiga's CPU in this timing mode.
    pub fn cpuSpeed(self: TimingMode) Hz {
        return switch (self) {
            .pal => 7_093_790, // 7.09mHz
            .ntsc => 7_159_090, // 7.16mHz
        };
    }

    /// Returns the rate in Hz of the Amiga's clock constant (1/2 the CPU clock).
    pub fn clockConstant(self: TimingMode) Hz {
        return self.cpuSpeed() / 2;
    }

    /// Returns the rate in Hz of the Amiga's CIA timer chip (1/10th the CPU clock).
    pub fn ciaRate(self: TimingMode) Hz {
        return self.cpuSpeed() / 10;
    }

    /// Converts a duration expressed as a number of video frames into milliseconds.
    pub fn msFromFrameCount(self: TimingMode, frame_count: vm.FrameCount) Milliseconds {
        return (frame_count * std.time.ms_per_s) / self.frameRate();
    }

    /// Converts an audio frequency expressed as a period of the Amiga clock constant into Hz.
    /// Precondition: period must be >0.
    pub fn hzFromPeriod(self: TimingMode, period: audio.Period) Hz {
        // The Amiga's clock constant defines how many clcok ticks there are in a second,
        // which varied between PAL and NTSC Amigas. The Amiga's audio hardware expected
        // the pitch of a sound to be expressed as a number of clock ticks.
        // Lower values meant higher frequencies.
        //
        // Another World's music tracks - and other Amiga MOD formats - stored frequencies
        // as Amiga period values for convenience.
        //
        // References:
        // -----------
        // - Reference implementation: https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/ blob/mastesrcsfxplayer.cpp#L194
        // - Clock speed discussion: https://retrocomputing.stackexchange.com/questions/2146/    reason-for-the-amiga-clock-speed
        // - ProTracker MOD format discussion: https://www.exotica.org.uk/wiki/Protracker
        // - Amiga hardware manual: http://amiga.nvg.org/amiga/reference/Hardware_Manual_guide/node00DE.html

        std.debug.assert(period > 0);
        return self.clockConstant() / period;
    }

    /// Converts a tempo expressed in ticks of the Amiga CIA clock
    /// into milliseconds per row of a music track.
    pub fn msFromTempo(self: TimingMode, tempo: audio.Tempo) Milliseconds {
        // The reference implementation used the following formula: ms/row = tempo * 60 / 7050
        // See: https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/sfxplayer.cpp#L42
        // That formula seems like a ballpark approximation of the Amiga's hardware timing:
        // 7050 is suspiciously close to the PAL CIA clock / 1000 (7093.79).
        //
        // The tempo values used in Another World's DOS music tracks and bytecode were:
        // 12168 = ~103.5ms/row by that formula
        // 15000 = ~127.7
        // 15240 = ~129.7
        // 15700 = ~133.6
        // 15900 = ~135.3
        //
        // Another World almost certainly adapted an existing MOD format for its music data,
        // so this should correspond to some standard.
        //
        // Early MOD music formats were timed off the video vblank interrupt and expressed
        // the tempo of a track as "video frames per row". Tracks commonly set this value
        // to 6, equivalent to 120 ms/row in PAL's 50hz clock or 100ms/row in NTSC's 60hz clock.
        // Reference: https://modarchive.org/forums/index.php?topic=2709.0
        //
        // Later MOD formats used a CIA timer interrupt rather than the vblank interrupt
        // to allow more fine-grained control over the timing. They largely kept to 6
        // "frames" per row, but varied the duration of the "frame" itself by setting a different
        // value in the 16-bit CIA timer. Thus the tempo was expressed relative to ticks
        // of the CIA clock.
        //
        // Judging from the scale of the tempo values above, Another World's music tracks
        // assumed 6 frames per row and expressed the tempo in raw CIA ticks.
        //
        // TODO: factor out frames_per_row from this and apply it in the music player?
        const frames_per_row = 6;
        return (@as(Milliseconds, tempo) * frames_per_row * std.time.ms_per_s) / self.ciaRate();
    }
};
