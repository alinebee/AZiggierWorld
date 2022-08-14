const Opcode = @import("../values/opcode.zig").Opcode;
const Program = @import("../machine/program.zig").Program;
const Machine = @import("../machine/machine.zig").Machine;

const Point = @import("../values/point.zig").Point;
const StringID = @import("../values/string_id.zig");
const ColorID = @import("../values/color_id.zig").ColorID;

/// The width in pixels of each column of glyphs.
const column_width = 8;

pub const DrawString = struct {
    /// The ID of the string to draw.
    string_id: StringID.Raw,
    /// The color to draw the string in.
    color_id: ColorID,
    /// The point in screen space at which to draw the string, relative to the top left corner of the screen.
    point: Point,

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 6 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(_: Opcode.Raw, program: *Program) ParseError!Self {
        const string_id = try program.read(StringID.Raw);

        const raw_x = try program.read(u8);
        const raw_y = try program.read(u8);

        const raw_color_id = try program.read(ColorID.Raw);

        return Self{
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

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *Machine) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) !void {
        return machine.drawString(self.string_id, self.color_id, self.point);
    }

    // - Exported constants -

    pub const opcode = Opcode.DrawString;

    pub const ParseError = Program.ReadError || StringID.Error || ColorID.Error;

    // -- Bytecode examples --

    pub const Fixtures = struct {
        const raw_opcode = opcode.encode();

        /// Example bytecode that should produce a valid instruction.
        pub const valid = [6]u8{ raw_opcode, 0xDE, 0xAD, 20, 100, 15 };

        const invalid_color_id = [6]u8{ raw_opcode, 0xDE, 0xAD, 20, 100, 255 };
    };
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = @import("../machine/test_helpers/mock_machine.zig").mockMachine;

test "parse parses valid bytecode and consumes 6 bytes" {
    const instruction = try expectParse(DrawString.parse, &DrawString.Fixtures.valid, 6);

    try testing.expectEqual(0xDEAD, instruction.string_id);
    try testing.expectEqual(ColorID.cast(15), instruction.color_id);
    try testing.expectEqual(160, instruction.point.x);
    try testing.expectEqual(100, instruction.point.y);
}

test "parse returns error.InvalidColorID on out of range color and consumes 6 bytes" {
    try testing.expectError(
        error.InvalidColorID,
        expectParse(DrawString.parse, &DrawString.Fixtures.invalid_color_id, 6),
    );
}

test "execute calls drawString with correct parameters" {
    const instruction = DrawString{
        .string_id = 0xDEAD,
        .color_id = ColorID.cast(15),
        .point = .{
            .x = 160,
            .y = 100,
        },
    };

    var machine = mockMachine(struct {
        pub fn drawString(string_id: StringID.Raw, color_id: ColorID, point: Point) !void {
            try testing.expectEqual(0xDEAD, string_id);
            try testing.expectEqual(ColorID.cast(15), color_id);
            try testing.expectEqual(160, point.x);
            try testing.expectEqual(100, point.y);
        }
    });

    try instruction._execute(&machine);
    try testing.expectEqual(1, machine.call_counts.drawString);
}

test "execute passes along error.InvalidStringID if machine cannot find appropriate string" {
    const instruction = DrawString{
        .string_id = 0xDEAD,
        .color_id = ColorID.cast(15),
        .point = .{
            .x = 160,
            .y = 100,
        },
    };

    var machine = mockMachine(struct {
        pub fn drawString(_: StringID.Raw, _: ColorID, _: Point) !void {
            return error.InvalidStringID;
        }
    });

    try testing.expectError(error.InvalidStringID, instruction._execute(&machine));
}
