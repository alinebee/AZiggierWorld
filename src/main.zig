const std = @import("std");
const testing = std.testing;
const meta = std.meta;

test "Run all tests" {
    meta.refAllDecls(@import("vm/instructions/instruction.zig"));
    meta.refAllDecls(@import("integration_tests/resource_loading.zig"));
}
