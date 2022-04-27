//! Tests that the non-interactive Another World introduction runs in its entirety
//! and ends by starting the first gameplay game part, without errors or looping indefinitely.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const Machine = @import("../machine/machine.zig");
const Host = @import("../machine/host.zig");
const ResourceDirectory = @import("../resources/resource_directory.zig").ResourceDirectory;
const BufferID = @import("../values/buffer_id.zig");
const UserInput = @import("../machine/user_input.zig");

const ensureValidFixtureDir = @import("helpers.zig").ensureValidFixtureDir;
const testing = @import("../utils/testing.zig");
const log = @import("../utils/logging.zig").log;
const std = @import("std");

const CountingHost = struct {
    render_count: usize = 0,
    total_delay: usize = 0,
    max_delay: ?usize = null,
    min_delay: ?usize = null,

    const Self = @This();

    fn host(self: *Self) Host.Interface {
        return Host.Interface.init(self, bufferReady);
    }

    fn bufferReady(self: *Self, _: *const Machine.Instance, _: BufferID.Specific, delay: Host.Milliseconds) void {
        self.render_count += 1;
        self.total_delay += delay;

        if (self.max_delay) |*max_delay| {
            max_delay.* = @maximum(max_delay.*, delay);
        } else {
            self.max_delay = delay;
        }

        if (self.min_delay) |*min_delay| {
            min_delay.* = @minimum(min_delay.*, delay);
        } else {
            self.min_delay = delay;
        }
    }
};

/// The maximum number of tics to run the introduction cinematic for before deciding it has hanged.
/// The DOS Another World introduction takes 2611 tics.
const max_tics = 10_000;

test "Introduction runs successfully" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try ResourceDirectory.init(&game_dir);
    var host = CountingHost{};

    var machine = try Machine.new(testing.allocator, resource_directory.reader(), host.host(), .{
        .initial_game_part = .intro_cinematic,
        .seed = 0,
    });
    defer machine.deinit();

    const empty_input = UserInput.Instance{};

    var tics_without_render: usize = 0;
    var tics_with_single_render: usize = 0;
    var tics_with_multiple_renders: usize = 0;
    var max_renders_during_tic: ?usize = null;

    var tic_count: usize = 0;
    while (tic_count < max_tics) : (tic_count += 1) {
        const renders_before_tic = host.render_count;

        try machine.runTic(empty_input);

        const renders_after_tic = host.render_count;
        const renders_during_tic = renders_after_tic - renders_before_tic;

        switch (renders_during_tic) {
            0 => tics_without_render += 1,
            1 => tics_with_single_render += 1,
            else => tics_with_multiple_renders += 1,
        }

        if (max_renders_during_tic) |*max| {
            max.* = @maximum(max.*, renders_during_tic);
        } else {
            max_renders_during_tic = renders_during_tic;
        }

        if (machine.scheduled_game_part) |next_game_part| {
            try testing.expectEqual(.gameplay1, next_game_part);
            break;
        }
    } else {
        // If we reach here without breaking, the introduction has stalled somehow
        // and would probably never complete.
        return error.ExceededMaxTics;
    }

    // Uncomment to print out statistics
    std.testing.log_level = .debug;

    log.info("\nIntro statistics\n----", .{});
    log.info("Total tics: {}", .{tic_count});
    log.info("Total renders: {}", .{host.render_count});
    log.info("Tics without renders: {}", .{tics_without_render});
    log.info("Tics with a single render: {}", .{tics_with_single_render});
    log.info("Tics with multiple renders: {}", .{tics_with_multiple_renders});
    log.info("Total frame delay: {} ms", .{host.total_delay});
    log.info("Min frame delay: {} ms", .{host.min_delay});
    log.info("Max frame delay: {} ms", .{host.max_delay});
}
