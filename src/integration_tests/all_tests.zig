const testing = @import("utils").testing;

test "Run all integration tests" {
    // Dumps noisy information about resources loaded by each game part,
    // but doesn't actually test anything
    // testing.refAllDecls(@import("gamepart_sizes.zig"));

    testing.refAllDecls(@import("resource_loading.zig"));
    testing.refAllDecls(@import("bytecode_parsing.zig"));
    testing.refAllDecls(@import("polygon_parsing.zig"));
    testing.refAllDecls(@import("palette_parsing.zig"));
    testing.refAllDecls(@import("sound_parsing.zig"));
    testing.refAllDecls(@import("intro_execution.zig"));
}
