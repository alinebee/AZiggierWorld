const std = @import("std");
const testing = std.testing;
const meta = std.meta;

test "Run all tests" {
    meta.refAllDecls(@import("rendering/video_buffer.zig"));
    meta.refAllDecls(@import("rendering/polygon.zig"));
    meta.refAllDecls(@import("instructions/instruction.zig"));
    meta.refAllDecls(@import("integration_tests/resource_loading.zig"));
    meta.refAllDecls(@import("integration_tests/bytecode_parsing.zig"));
}
