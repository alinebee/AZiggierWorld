const Opcode = @import("../values/opcode.zig");
const Program = @import("../machine/program.zig");
const Machine = @import("../machine/machine.zig");

const Point = @import("../values/point.zig");
const StringID = @import("../values/string_id.zig");
const ColorID = @import("../values/color_id.zig");

pub const opcode = Opcode.Enum.DrawString;

pub const Instance = struct {
    /// The ID of the string to draw.
    string_id: StringID.Raw,
    /// The color to draw the string in.
    color_id: ColorID.Trusted,
    /// The point in screen space at which to draw the string, relative to the top left corner of the screen.
    point: Point.Instance,

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Instance, machine: *Machine.Instance) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) !void {
        return machine.drawString(self.string_id, self.color_id, self.point);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 6 bytes from the bytecode on success, including the opcode.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(_: Opcode.Raw, program: *Program.Instance) ParseError!Instance {
    const string_id = try program.read(StringID.Raw);

    const raw_x = try program.read(u8);
    const raw_y = try program.read(u8);

    const raw_color_id = try program.read(ColorID.Raw);

    return Instance{
        .string_id = string_id,
        .color_id = try ColorID.parse(raw_color_id),
        .point = .{
            // The raw X coordinate of a DrawString instruction goes from 0...39,
            // dividing the 320x200 screen into 8-pixel-wide columns.
            // Multiply it back out to get the location in pixels.
            .x = @as(Point.Coordinate, raw_x) * column_width,
            .y = @as(Point.Coordinate, raw_y),
        },
    };
}

pub const ParseError = Program.Error || StringID.Error || ColorID.Error;

/// The width in pixels of each column of glyphs.
const column_width = 8;

// -- Bytecode examples --

pub const Fixtures = struct {
    const raw_opcode = @enumToInt(opcode);

    /// Example bytecode that should produce a valid instruction.
    pub const valid = [6]u8{ raw_opcode, 0xDE, 0xAD, 20, 100, 15 };

    const invalid_color_id = [6]u8{ raw_opcode, 0xDE, 0xAD, 20, 100, 255 };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("../machine/test_helpers/mock_machine.zig");

test "parse parses valid bytecode and consumes 6 bytes" {
    const instruction = try expectParse(parse, &Fixtures.valid, 6);

    try testing.expectEqual(0xDEAD, instruction.string_id);
    try testing.expectEqual(15, instruction.color_id);
    try testing.expectEqual(160, instruction.point.x);
    try testing.expectEqual(100, instruction.point.y);
}

test "parse returns error.InvalidColorID on out of range color and consumes 6 bytes" {
    try testing.expectError(
        error.InvalidColorID,
        expectParse(parse, &Fixtures.invalid_color_id, 6),
    );
}

test "execute calls drawString with correct parameters" {
    const instruction = Instance{
        .string_id = 0xDEAD,
        .color_id = 15,
        .point = .{
            .x = 160,
            .y = 100,
        },
    };

    var machine = MockMachine.new(struct {
        pub fn drawString(string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
            try testing.expectEqual(0xDEAD, string_id);
            try testing.expectEqual(15, color_id);
            try testing.expectEqual(160, point.x);
            try testing.expectEqual(100, point.y);
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.drawString);
}

test "execute passes along error.InvalidStringID if machine cannot find appropriate string" {
    const instruction = Instance{
        .string_id = 0xDEAD,
        .color_id = 15,
        .point = .{
            .x = 160,
            .y = 100,
        },
    };

    var machine = MockMachine.new(struct {
        pub fn drawString(_: StringID.Raw, _: ColorID.Trusted, _: Point.Instance) !void {
            return error.InvalidStringID;
        }
    });

    try testing.expectError(error.InvalidStringID, instruction._execute(&machine));
}
