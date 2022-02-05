const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("lib_anotherworld", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    var benchmark = b.addExecutable("benchmark", "src/benchmark.zig");
    benchmark.setBuildMode(mode);
    benchmark.install();

    const run_benchmark_cmd = benchmark.run();
    run_benchmark_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_benchmark_cmd.addArgs(args);
    }

    const benchmark_step = b.step("benchmark", "Run library benchmarks");
    benchmark_step.dependOn(&run_benchmark_cmd.step);
}
