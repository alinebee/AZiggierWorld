pub const Machine = @import("vm/machine.zig").Machine;
pub const Video = @import("vm/video.zig").Video;
pub const Audio = @import("vm/audio.zig").Audio;
pub const Host = @import("vm/host.zig").Host;
pub const Stack = @import("vm/stack.zig").Stack;
pub const Program = @import("vm/program.zig").Program;
pub const UserInput = @import("vm/user_input.zig").UserInput;

pub const Register = @import("vm/register.zig");
pub const RegisterID = @import("vm/register_id.zig").RegisterID;
pub const ThreadID = @import("vm/thread_id.zig").ThreadID;
pub const BufferID = @import("vm/buffer_id.zig").BufferID;
pub const ChannelID = @import("vm/channel_id.zig").ChannelID;
pub const GamePart = @import("vm/game_part.zig").GamePart;

pub const mockMachine = @import("vm/test_helpers/mock_machine.zig").mockMachine;
