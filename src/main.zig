const std = @import("std");
const testing = std.testing;
const meta = std.meta;

test "Run all tests" {
    // Uncomment these if you have populated fixtures/dos with Another World game files.
    // meta.refAllDecls(@import("integration_tests/resource_loading.zig"));
    // meta.refAllDecls(@import("integration_tests/memlist_parsing.zig"));
    meta.refAllDecls(@import("vm/instructions/instruction.zig"));
}
