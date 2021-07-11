const std = @import("std");
const testing = std.testing;
const validFixturePath = @import("helpers.zig").validFixturePath;

test "Run all integration tests" {
    const game_path = validFixturePath(testing.allocator) catch return;
    defer testing.allocator.free(game_path);

    testing.refAllDecls(@import("resource_loading.zig"));
    testing.refAllDecls(@import("bytecode_parsing.zig"));
    testing.refAllDecls(@import("polygon_parsing.zig"));
}
