//! Unlike the other integration tests, which can be run by `zig build test`,
//! these benchmarks can only be run by `zig build benchmark`.

const Machine = @import("machine/machine.zig");
const Host = @import("machine/host.zig");
const ResourceDirectory = @import("resources/resource_directory.zig");
const Video = @import("machine/video.zig");
const BufferID = @import("values/buffer_id.zig");
const UserInput = @import("machine/user_input.zig");

const ensureValidFixtureDir = @import("integration_tests/helpers.zig").ensureValidFixtureDir;
const log = @import("utils/logging.zig").log;

const std = @import("std");

const Timer = std.time.Timer;

pub const log_level: std.log.Level = .info;

const max_iterations = 20;

var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .{};

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

/// Execute the Another World intro until it switches to the first gameplay section or exceeds a maximum number of tics.
fn runIntro(allocator: std.mem.Allocator, game_dir: *std.fs.Dir) !void {
    const max_tics = 10000;

    var resource_directory = try ResourceDirectory.new(game_dir);
    var host = RenderHost{};

    const empty_input = UserInput.Instance{};

    var machine = try Machine.new(allocator, resource_directory.reader(), host.host(), .intro_cinematic, 0);
    defer machine.deinit();

    var tic_count: usize = 0;
    while (tic_count < max_tics) : (tic_count += 1) {
        try machine.runTic(empty_input);

        // End the as soon as the intro
        if (machine.scheduled_game_part != null) {
            std.log.debug("Intro completed after {} tics", .{tic_count});
            return;
        }
    } else {
        return error.ExceededMaxTics;
    }
}

pub fn main() !void {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    const allocator = general_purpose_allocator.allocator();

    var samples: [max_iterations]u64 = undefined;

    var timer = try Timer.start();
    for (samples) |*iteration, iteration_count| {
        std.log.info("Iteration #{}", .{iteration_count});
        timer.reset();

        runIntro(allocator, &game_dir) catch |err| {
            log.warn("Iteration #{} failed with error {}", .{ iteration_count, err });
        };

        iteration.* = timer.lap();
    }

    std.sort.sort(u64, &samples, {}, comptime std.sort.asc(u64));

    // Discard lowest and highest samples to account for noise
    const usable_samples = samples[1 .. samples.len - 1];

    var total: u64 = 0;
    var min: u64 = std.math.maxInt(u64);
    var max: u64 = 0;
    for (usable_samples) |sample| {
        total += sample;
        if (sample < min) min = sample;
        if (sample > max) max = sample;
    }

    const median = usable_samples[usable_samples.len / 2];
    const mean = total / usable_samples.len;

    log.info(
        \\Iterations: {}
        \\Total time: {}nsec
        \\Min iteration time: {}nsec
        \\Max iteration time: {}nsec
        \\Mean iteration time: {}nsec
        \\Median iteration time: {}nsec
    , .{
        max_iterations,
        total,
        min,
        max,
        mean,
        median,
    });
}

const testing = @import("utils/testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(@This());
}
