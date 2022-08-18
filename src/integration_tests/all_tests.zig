const testing = @import("utils").testing;

test "Run all integration tests" {
    testing.refAllDecls(@import("resource_loading.zig"));
    testing.refAllDecls(@import("bytecode_parsing.zig"));
    testing.refAllDecls(@import("polygon_parsing.zig"));
    testing.refAllDecls(@import("palette_parsing.zig"));
    testing.refAllDecls(@import("intro_execution.zig"));
}
