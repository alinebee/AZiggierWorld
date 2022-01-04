const std = @import("std");
const testing = std.testing;

test "Run all tests" {
    testing.refAllDecls(@import("integration_tests/all_tests.zig"));
    testing.refAllDecls(@import("machine/machine.zig"));
    testing.refAllDecls(@import("machine/user_input.zig"));
}
