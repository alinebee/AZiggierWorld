const std = @import("std");
const testing = std.testing;

test "Run all tests" {
    testing.refAllDecls(@import("rendering/video_buffer.zig"));
    testing.refAllDecls(@import("rendering/polygon.zig"));
    testing.refAllDecls(@import("instructions/instruction.zig"));
    testing.refAllDecls(@import("integration_tests/resource_loading.zig"));
    testing.refAllDecls(@import("integration_tests/bytecode_parsing.zig"));
}
