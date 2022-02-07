//! Measures the performance of a block of code by executing it multiple times
//! and sampling each iteration.
//! Messily adapted from https://github.com/ziglang/gotta-go-fast.

const std = @import("std");

/// The result of a measure operation.
pub const Result = struct {
    /// The total number of iterations.
    iterations: usize,
    /// The total time taken for all iterations, in nanoseconds.
    total_time: u64,
    /// The minimum time a single iteration took, in nanoseconds.
    min_iteration_time: u64,
    /// The maximum time a single iteration took, in nanoseconds.
    max_iteration_time: u64,
    /// The mean time a single iteration took, in nanoseconds.
    mean_iteration_time: u64,
    /// The median time a single iteration took, in nanoseconds.
    median_iteration_time: u64,

    /// Print the results in a human-readable format.
    pub fn format(self: Result, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer,
            \\Iterations: {}
            \\Total time: {}nsec
            \\Min iteration time: {}nsec
            \\Max iteration time: {}nsec
            \\Mean iteration time: {}nsec
            \\Median iteration time: {}nsec
        , .{
            self.iterations,
            self.total_time,
            self.min_iteration_time,
            self.max_iteration_time,
            self.mean_iteration_time,
            self.median_iteration_time,
        });
    }
};

/// Execute a specific function for n iterations, measuring the mean and median time taken
/// to execute the function.
///
/// Parameters:
/// subject: A struct whose execute() function implements the behavior that should be measured.
/// max_iterations: The number of times to run the subject's execute() function. Must be at least 3.
///
/// Returns: A Result struct describing the min, max and average times of the iterations.
pub fn measure(subject: anytype, comptime max_iterations: usize) !Result {
    // We throw away the fastest and slowest samples, so we need at least 1 other iteration on top of those.
    std.debug.assert(max_iterations >= 3);

    var timer = try std.time.Timer.start();

    var samples: [max_iterations]u64 = undefined;

    for (samples) |*sample| {
        timer.reset();
        try subject.execute();
        sample.* = timer.lap();
    }

    std.sort.sort(u64, &samples, {}, comptime std.sort.asc(u64));

    // Discard lowest and highest samples to allow for system noise
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

    return Result{
        .iterations = max_iterations,
        .total_time = total,
        .min_iteration_time = min,
        .max_iteration_time = max,
        .mean_iteration_time = mean,
        .median_iteration_time = median,
    };
}

// -- Tests --

const testing = @import("testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(@This());
}
