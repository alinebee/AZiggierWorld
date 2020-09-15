const Opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");
const Video = @import("../video.zig");

const Point = @import("../types/point.zig");
const StringID = @import("../types/string_id.zig");
const ColorID = @import("../types/color_id.zig");

pub const Error = Program.Error || StringID.Error || ColorID.Error;

pub const Instance = struct {
    /// The ID of the string to draw.
    string_id: StringID.Raw,
    /// The color to draw the string in.
    color_id: ColorID.Trusted,
    /// The point in screen space at which to draw the string.
    /// TODO: document which point in the string this is relative to: top left?
    point: Point.Instance,

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Instance, machine: *Machine.Instance) Error!void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) Error!void {
        return machine.drawString(self.string_id, self.color_id, self.point);
    }
};

/// Parse the next instruction from a bytecode program.
/// Consumes 5 bytes from the bytecode on success.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    const string_id = try program.read(StringID.Raw);
    const raw_color_id = try program.read(ColorID.Raw);
    const raw_x = try program.read(u8);
    const raw_y = try program.read(u8);

    return Instance{
        .string_id = string_id,
        .color_id = try ColorID.parse(raw_color_id),
        .point = .{
            .x = @as(Point.Coordinate, raw_x),
            .y = @as(Point.Coordinate, raw_y),
        },
    };
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    const raw_opcode = @enumToInt(Opcode.Enum.DrawString);

    pub const valid = [_]u8{ raw_opcode, 0xDE, 0xAD, 15, 160, 100 };
    pub const invalid_color_id = [_]u8{ raw_opcode, 0xDE, 0xAD, 255, 160, 100 };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("test_helpers/mock_machine.zig");

test "parse parses valid bytecode" {
    const instruction = try expectParse(parse, &BytecodeExamples.valid, 5);

    testing.expectEqual(0xDEAD, instruction.string_id);
    testing.expectEqual(15, instruction.color_id);
    testing.expectEqual(160, instruction.point.x);
    testing.expectEqual(100, instruction.point.y);
}

test "parse returns error.InvalidColorID on out of range color" {
    testing.expectError(
        error.InvalidColorID,
        expectParse(parse, &BytecodeExamples.invalid_color_id, 5),
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
            testing.expectEqual(0xDEAD, string_id);
            testing.expectEqual(15, color_id);
            testing.expectEqual(160, point.x);
            testing.expectEqual(100, point.y);
        }
    });

    try instruction._execute(&machine);
    testing.expectEqual(1, machine.call_counts.drawString);
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
        pub fn drawString(string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
            return error.InvalidStringID;
        }
    });

    testing.expectError(error.InvalidStringID, instruction._execute(&machine));
}
