const std = @import("std");
const testing = std.testing;

test "Run all tests" {
    testing.refAllDecls(@import("integration_tests/all_tests.zig"));
    testing.refAllDecls(@import("instructions/instruction.zig"));
    testing.refAllDecls(@import("machine/memory.zig"));
    testing.refAllDecls(@import("machine/video.zig"));
}
