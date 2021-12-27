const std = @import("std");
const testing = std.testing;

test "Run all tests" {
    testing.refAllDecls(@import("integration_tests/all_tests.zig"));
    testing.refAllDecls(@import("rendering/video_buffer.zig"));
    testing.refAllDecls(@import("rendering/polygon.zig"));
    testing.refAllDecls(@import("instructions/instruction.zig"));
    testing.refAllDecls(@import("machine/memory.zig"));
}
