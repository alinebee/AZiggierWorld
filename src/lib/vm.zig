pub const Machine = @import("vm/machine.zig").Machine;
pub const Host = @import("vm/host.zig").Host;
pub const Stack = @import("vm/stack.zig").Stack;
pub const UserInput = @import("vm/user_input.zig").UserInput;

pub const Register = @import("vm/register.zig");
pub const RegisterID = @import("vm/register_id.zig").RegisterID;
pub const ThreadID = @import("vm/thread_id.zig").ThreadID;
pub const BufferID = @import("vm/buffer_id.zig").BufferID;
pub const GamePart = @import("vm/game_part.zig").GamePart;

pub const PolygonSource = @import("vm/video.zig").Video.PolygonSource;
pub const HostSurface = @import("vm/video.zig").Video.HostSurface;
pub const ResolvedBufferID = @import("vm/video.zig").Video.ResolvedBufferID;

pub const FrameCount = Register.Unsigned;
pub const Milliseconds = @import("anotherworld.zig").timing.Milliseconds;

pub const AudioBuffer = []const @import("anotherworld.zig").audio.Sample;

/// The default sample rate at which the virtual machine will mix game audio.
pub const DefaultSampleRate = 22050;

pub const mockMachine = @import("vm/test_helpers/mock_machine.zig").mockMachine;
