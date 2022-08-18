//! Tests that Instruction.parse parses all bytecode programs from the original Another World.
//! Requires that the `fixtures/dos` folder contains Another World DOS game files.

const anotherworld = @import("anotherworld");
const instructions = anotherworld.instructions;
const resources = anotherworld.resources;
const log = anotherworld.log;

const Program = @import("../machine/program.zig").Program;

const testing = @import("utils").testing;
const meta = @import("utils").meta;
const ensureValidFixtureDir = @import("helpers.zig").ensureValidFixtureDir;

const std = @import("std");

/// Records and prints the details of a bytecode instruction that could not be parsed.
const ParseFailure = struct {
    resource_id: usize,
    offset: usize,
    parsed_bytes: [8]u8,
    parsed_count: usize,
    err: anyerror,

    fn init(resource_id: usize, program: *Program, offset: usize, err: anyerror) ParseFailure {
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
        if (meta.intToEnum(instructions.Opcode, self.parsed_bytes[0])) |value| {
            return @tagName(value);
        } else |_| {
            return "Unknown";
        }
    }

    pub fn format(self: ParseFailure, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Program resource #{} at offset {}\nOpcode: {s}\nParsed bytes: {s}\nError: {s}", .{
            self.resource_id,
            self.offset,
            self.opcodeName(),
            std.fmt.fmtSliceHexUpper(self.parsed_bytes[0..self.parsed_count]),
            self.err,
        });
    }
};

test "Instruction.parse parses all programs in fixture bytecode" {
    var game_dir = try ensureValidFixtureDir();
    defer game_dir.close();

    var resource_directory = try resources.ResourceDirectory.init(&game_dir);
    const reader = resource_directory.reader();

    var failures = std.ArrayList(ParseFailure).init(testing.allocator);
    defer failures.deinit();

    for (reader.resourceDescriptors()) |descriptor, index| {
        if (descriptor.type != .bytecode) continue;

        const data = try reader.allocReadResource(testing.allocator, descriptor);
        defer testing.allocator.free(data);

        var program = try Program.init(data);

        while (program.isAtEnd() == false) {
            const last_valid_address = program.counter;
            if (instructions.Instruction.parse(&program)) |instruction| {
                switch (instruction) {
                    // .ControlResources => |control_resources| {
                    //     switch (control_resources) {
                    //         .start_game_part => |game_part| log.debug("\nGame part: {X}\n", .{game_part}),
                    //         else => {},
                    //     }
                    // },
                    else => {},
                }
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
        log.err("\n{} instruction(s) failed to parse:\n", .{failures.items.len});
        for (failures.items) |failure| {
            log.err("\n{s}\n\n", .{failure});
        }
    }

    try testing.expectEqual(0, failures.items.len);
}
