const std = @import("std");
const Builder = std.build.Builder;
const SDLSdk = @import("vendor/SDL.zig/Sdk.zig");

// Define a package for generic utility functions
const utils_package = std.build.Pkg{
    .name = "utils",
    .path = .{ .path = "./src/utils/utils.zig" },
};

// Define a package for Another World library files
const lib_package = std.build.Pkg{
    .name = "anotherworld",
    .path = .{ .path = "./src/lib/anotherworld.zig" },
    .dependencies = &[_]std.build.Pkg{
        utils_package,
    },
};

pub fn build(b: *Builder) !void {
    b.setPreferredReleaseMode(.ReleaseSafe);
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    // On MacOS, add homebrew to search path to make it easier to find SDL2
    if (b.host.target.os.tag == .macos) {
        b.addSearchPrefix("/opt/homebrew/");
    }

    const sdl_sdk = SDLSdk.init(b);
    const sdl_package = sdl_sdk.getWrapperPackage("sdl2");

    // -- Main executable --
    const exe = b.addExecutable("anotherworld", "src/main.zig");
    {
        exe.setBuildMode(mode);
        exe.setTarget(target);

        sdl_sdk.link(exe, .dynamic);
        exe.addPackage(sdl_package);
        exe.addPackage(utils_package);
        exe.addPackage(lib_package);

        exe.install();
    }

    // -- Run executable step --
    const run_exe_step = b.step("run", "Run executable");
    {
        const run = exe.run();
        run_exe_step.dependOn(&run.step);

        // Use the location of this build.zig as the working directory,
        // instead of the executable's location, so that it will resolve
        // relative paths to game directories in a more intuitive way.
        run.cwd = b.build_root;

        // Allow a custom game directory to be specified on the command line
        // via zig build run -- path/to/another/world.
        // If no custom path was specified, use the project's own fixture path.
        if (b.args) |args| {
            run.addArgs(args);
        } else {
            // FIXME: this requires the `fixtures/dos` directory to exist; if it doesn't,
            // all build steps will fail even if the user does not care about `zig build run`.
            // Instead, we should try to resolve the path dynamically when executing the run step.
            const fixture_path = b.pathFromRoot("fixtures/dos");
            run.addArg(fixture_path);
        }
    }

    // -- Test step --
    const test_step = b.step("test", "Run tests");
    {
        var tests = b.addTest("src/main.zig");
        tests.setBuildMode(mode);
        tests.setTarget(target);

        sdl_sdk.link(tests, .dynamic);
        tests.addPackage(sdl_package);
        tests.addPackage(utils_package);
        tests.addPackage(lib_package);

        test_step.dependOn(&tests.step);
    }

    // -- Benchmark step --
    const benchmark_step = b.step("benchmark", "Run benchmarks");
    {
        var benchmark = b.addExecutable("benchmark", "src/benchmark.zig");
        benchmark.setBuildMode(.ReleaseSafe);
        benchmark.setTarget(target);
        benchmark.addPackage(utils_package);
        benchmark.addPackage(lib_package);

        const run = benchmark.run();
        benchmark_step.dependOn(&run.step);
    }
}
