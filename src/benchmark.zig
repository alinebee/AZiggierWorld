//! Unlike the other integration tests, which can be run by `zig build test`,
//! these benchmarks can only be run by `zig build benchmark`.

const Machine = @import("machine/machine.zig");
const Host = @import("machine/host.zig");
const ResourceDirectory = @import("resources/resource_directory.zig");
const Video = @import("machine/video.zig");
const BufferID = @import("values/buffer_id.zig");
const UserInput = @import("machine/user_input.zig");

const ensureValidFixtureDir = @import("integration_tests/helpers.zig").ensureValidFixtureDir;
const measure = @import("utils/measure.zig").measure;
const log = @import("utils/logging.zig").log;

const std = @import("std");

pub const log_level: std.log.Level = .info;

/// A virtual machine host that renders each frame to a surface as soon as it is ready, with no delays.
const RenderHost = struct {
    surface: Video.HostSurface = undefined,

    const Self = @This();

    fn host(self: *Self) Host.Interface {
        return Host.Interface.init(self, bufferReady);
    }
    fn bufferReady(self: *Self, video: *const Video.Instance, buffer_id: BufferID.Specific, _: Host.Milliseconds) void {
        video.renderBufferToSurface(buffer_id, &self.surface) catch |err| {
            switch (err) {
                // The Another World intro attempts to render at least 4 times before any palette is selected.
                error.PaletteNotSelected => log.debug("Rendered with no palette selected", .{}),
                else => unreachable,
            }
        };
    }
};

/// Creates a new VM and executes the Another World intro until it switches
/// to the first gameplay section or exceeds a maximum number of tics.
const Subject = struct {
    allocator: std.mem.Allocator,
    game_dir: std.fs.Dir,
    iteration_count: usize = 0,

    pub fn execute(self: *Subject) !void {
        self.iteration_count += 1;
        log.debug("Iteration #{}", .{self.iteration_count});

        const max_tics = 10000;

        var resource_directory = try ResourceDirectory.new(&self.game_dir);
        var host = RenderHost{};

        const empty_input = UserInput.Instance{};

        var machine = try Machine.new(self.allocator, resource_directory.reader(), host.host(), .{
            .initial_game_part = .intro_cinematic,
            .seed = 0,
        });
        defer machine.deinit();

        var tic_count: usize = 0;
        while (tic_count < max_tics) : (tic_count += 1) {
            try machine.runTic(empty_input);

            if (machine.scheduled_game_part != null) {
                log.debug("Intro completed after {} tics", .{tic_count});
                return;
            }
        } else {
            return error.ExceededMaxTics;
        }
    }
};

const max_duration_in_sec = 5;
const max_iterations = 10_000;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var subject = Subject{
        .allocator = gpa.allocator(),
        .game_dir = game_dir,
    };

    const result = try measure(&subject, max_iterations, max_duration_in_sec * std.time.ns_per_s);

    log.info(
        \\
        \\Another World intro benchmark:
        \\------------------------------
        \\{}
    , .{result});
}

const testing = @import("utils/testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(@This());
}
