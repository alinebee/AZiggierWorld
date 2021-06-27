//! Tests that parseNextInstruction all bytecode programs from the original Another World.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const Instruction = @import("../instructions/instruction.zig");
const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const ResourceLoader = @import("../resources/resource_loader.zig");

const testing = @import("../utils/testing.zig");
const instrospection = @import("../utils/introspection.zig");
const validFixturePath = @import("helpers.zig").validFixturePath;
const std = @import("std");

const ParseFailure = struct {
    resource_id: usize,
    offset: usize,
    parsed_bytes: [8]u8,
    parsed_count: usize,
    err: Instruction.Error,

    fn init(resource_id: usize, program: *Program.Instance, offset: usize, err: Instruction.Error) ParseFailure {
        const parsed_bytes = program.bytecode[offset..program.counter];

        var self = ParseFailure{
            .resource_id = resource_id,
            .offset = offset,
            .parsed_bytes = undefined,
            .parsed_count = parsed_bytes.len,
            .err = err,
        };
        std.mem.copy(u8, &self.parsed_bytes, parsed_bytes);
        return self;
    }

    fn opcodeName(self: ParseFailure) []const u8 {
        if (instrospection.intToEnum(Opcode.Enum, self.parsed_bytes[0])) |value| {
            return @tagName(value);
        } else |err| {
            return "Unknown";
        }
    }

    pub fn format(self: ParseFailure, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Resource #{} at {}\nOpcode: {s}\nBytes: {s}\nError: {s}", .{
            self.resource_id,
            self.offset,
            self.opcodeName(),
            std.fmt.fmtSliceHexUpper(self.parsed_bytes[0..self.parsed_count]),
            self.err,
        });
    }
};

test "parseNextInstruction parses all programs in fixture bytecode" {
    const game_path = validFixturePath(testing.allocator) catch return;
    defer testing.allocator.free(game_path);

    const loader = try ResourceLoader.new(testing.allocator, game_path);
    defer loader.deinit();

    var failures = std.ArrayList(ParseFailure).init(testing.allocator);
    defer failures.deinit();

    for (loader.resource_descriptors) |descriptor, index| {
        if (descriptor.type != .bytecode) continue;

        const data = try loader.readResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        var program = Program.Instance{ .bytecode = data };

        var last_valid_address = program.counter;
        while (program.counter < program.bytecode.len) : (last_valid_address = program.counter) {
            if (Instruction.parseNextInstruction(&program)) {
                // Instruction parsing succeeded, hooray!
            } else |err| {
                // Log and continue parsing after encountering a failure
                try failures.append(ParseFailure.init(
                    index,
                    &program,
                    last_valid_address,
                    err,
                ));
            }
        }
    }

    if (failures.items.len > 0) {
        std.debug.print("\n{} instruction(s) failed to parse:\n", .{failures.items.len});
        for (failures.items) |failure| {
            std.debug.print("\n{s}\n\n", .{failure});
        }
    }

    try testing.expectEqual(0, failures.items.len);
}
