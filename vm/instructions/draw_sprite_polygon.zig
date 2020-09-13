const Opcode = @import("../types/opcode.zig");
const Program = @import("../types/program.zig");
const Machine = @import("../machine.zig");
const Video = @import("../video.zig");
const Point = @import("../types/point.zig");

/// Draw a polygon at a location and zoom level that are either hardcoded constants
/// or dynamic values read from registers.
pub const Instance = struct {
    /// The source location from which to read polygon data.
    source: Video.PolygonSource,

    /// The address within the polygon source from which to read polygon data.
    address: Video.PolygonAddress,

    /// The source for the X offset at which to draw the polygon.
    x: union(enum) {
        constant: Point.Coordinate,
        register: Machine.RegisterID,
    },

    /// The source for the Y offset at which to draw the polygon.
    y: union(enum) {
        constant: Point.Coordinate,
        register: Machine.RegisterID,
    },

    /// The source for the scale at which to draw the polygon.
    scale: union(enum) {
        default,
        constant: Video.PolygonScale,
        register: Machine.RegisterID,
    },

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub inline fn execute(self: Instance, machine: *Machine.Instance) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Instance, machine: anytype) !void {
        const x = switch (self.x) {
            .constant => |constant| constant,
            .register => |id| machine.registers[id],
        };
        const y = switch (self.y) {
            .constant => |constant| constant,
            .register => |id| machine.registers[id],
        };
        const scale = switch (self.scale) {
            .constant => |constant| constant,
            // TODO: return an error for out-of-range scale values?
            .register => |id| @truncate(Video.PolygonScale, @bitCast(u16, machine.registers[id])),
            .default => null,
        };

        try machine.drawPolygon(self.source, self.address, .{ .x = x, .y = y }, scale);
    }
};

pub const Error = Program.Error;

/// Parse the next instruction from a bytecode program.
/// Consumes n bytes from the bytecode on success, not including the opcode itself.
/// Returns an error if the bytecode could not be read or contained an invalid instruction.
pub fn parse(raw_opcode: Opcode.Raw, program: *Program.Instance) Error!Instance {
    var self: Instance = undefined;

    // Unlike DrawBackgroundPolygon, which treats the lower 7 bits of the opcode as the top part of the polygon address,
    // this operation reads two whole bytes for the polygon address and uses the opcode bits for other parts of the
    // instruction (see below.)
    // It interprets the raw polygon address same way as DrawBackgroundPolygon though,
    // right-shifting by one to land on an even address boundary.
    self.address = (try program.read(Video.PolygonAddress)) << 1;

    // The low 6 bits of the opcode byte determine where to read the x, y and scale values from,
    // and therefore how many bytes to consume for the operation.
    // This opcode byte has a layout of `01|xx|yy|ss`, where:
    //
    // - `01` was the initial opcode identifier that indicated this as a DrawSpritePolygon instruction
    // in the first place.
    //
    // - `xx` controls where to read the X offset from:
    //   - 00: read next 2 bytes as signed 16-bit constant
    //   - 01: read next byte as ID of register containing X coordinate
    //   - 10: read next byte as unsigned 8-bit constant
    //   - 11: read next byte as unsigned 8-bit constant, add 256
    //     (necessary since an 8-bit X coordinate can't address an entire 320-pixel-wide screen)
    //
    // - `yy` controls where to read the Y offset from:
    //   - 00: read next 2 bytes as signed 16-bit constant
    //   - 01: read next byte as ID of register containing Y coordinate
    //   - 10, 11: read next byte as unsigned 8-bit constant
    //
    // - `ss` controls where to read the scale from and which memory to read region polygon data from:
    //   - 00: use `.polygons` region, set default scale
    //   - 01: use `.polygons` region, read next byte as ID of register containing scale
    //   - 10: use `.polygons` region, read next byte as unsigned 8-bit constant
    //   - 11: use `.animations` region, set default scale

    const raw_x     = @truncate(u2, raw_opcode >> 4);
    const raw_y     = @truncate(u2, raw_opcode >> 2);
    const raw_scale = @truncate(u2, raw_opcode);

    self.x = switch (raw_x) {
        0b00 => .{ .constant = try program.read(Point.Coordinate) },
        0b01 => .{ .register = try program.read(Machine.RegisterID) },
        0b10 => .{ .constant = @as(Point.Coordinate, try program.read(u8)) },
        0b11 => .{ .constant = @as(Point.Coordinate, try program.read(u8)) + 256 },
    };

    self.y = switch (raw_y) {
        0b00 => .{ .constant = try program.read(Point.Coordinate) },
        0b01 => .{ .register = try program.read(Machine.RegisterID) },
        0b10, 0b11 => .{ .constant = @as(Point.Coordinate, try program.read(u8)) },
    };

    switch (raw_scale) {
        0b00 => {
            self.source = .polygons;
            self.scale = .default;
        },
        0b01 => {
            self.source = .polygons;
            self.scale = .{ .register = try program.read(Machine.RegisterID) };
        },
        0b10 => {
            self.source = .polygons;
            self.scale = .{ .constant = try program.read(Video.PolygonScale) };
        },
        0b11 => {
            self.source = .animations;
            self.scale = .default;
        },
    }

    return self;
}

// -- Bytecode examples --

pub const BytecodeExamples = struct {
    pub const registers = [_]u8{
        0b01_01_01_01,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        1, 2, 3,                    // register IDs for x, y and scale
    };

    pub const wide_constants = [_]u8{
        0b01_00_00_10,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        0b1011_0110, 0b0010_1011,   // x constant (-18901 in two's-complement)
        0b0000_1101, 0b1000_1110,   // y constant (+3470 in two's-complement)
        255,                        // scale
    };

    pub const short_constants = [_]u8{
        0b01_10_10_10,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        160, 100,                   // constants for x and y
        255,                        // scale
    };

    pub const short_boosted_x_constants = [_]u8{
        0b01_11_10_10,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        64, 200,                    // constants for x + 256 and y
        255,                        // scale
    };

    pub const default_scale_from_polygons = [_]u8{
        0b01_10_10_00,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        160, 100,                   // constants for x and y
    };

    pub const default_scale_from_animations = [_]u8{
        0b01_10_10_11,              // opcode
        0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
        160, 100,                   // constants for x and y
    };
};

// -- Tests --

const testing = @import("../../utils/testing.zig");
const expectParse = @import("test_helpers/parse.zig").expectParse;
const MockMachine = @import("test_helpers/mock_machine.zig");

test "parse parses all-registers instruction and consumes 5 extra bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.registers, 5);

    testing.expectEqual(.polygons, instruction.source);
    // Address is right-shifted by 1
    testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    testing.expectEqual(.{ .register = 1 }, instruction.x);
    testing.expectEqual(.{ .register = 2 }, instruction.y);
    testing.expectEqual(.{ .register = 3 }, instruction.scale);
}

test "parse parses instruction with full-width constants and consumes 7 extra bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.wide_constants, 7);

    testing.expectEqual(.polygons, instruction.source);
    testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    testing.expectEqual(.{ .constant = -18901 }, instruction.x);
    testing.expectEqual(.{ .constant = 3470 }, instruction.y);
    testing.expectEqual(.{ .constant = 255 }, instruction.scale);
}

test "parse parses instruction with short constants and consumes 5 extra bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.short_constants, 5);

    testing.expectEqual(.polygons, instruction.source);
    testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    testing.expectEqual(.{ .constant = 160 }, instruction.x);
    testing.expectEqual(.{ .constant = 100 }, instruction.y);
    testing.expectEqual(.{ .constant = 255 }, instruction.scale);
}

test "parse parses instruction with short constants with boosted X and consumes 5 extra bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.short_boosted_x_constants, 5);

    testing.expectEqual(.polygons, instruction.source);
    testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    testing.expectEqual(.{ .constant = 64 + 256 }, instruction.x);
    testing.expectEqual(.{ .constant = 200 }, instruction.y);
    testing.expectEqual(.{ .constant = 255 }, instruction.scale);
}

test "parse parses instruction with default scale/polygon source and consumes 4 extra bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.default_scale_from_polygons, 4);

    testing.expectEqual(.polygons, instruction.source);
    testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    testing.expectEqual(.{ .constant = 160 }, instruction.x);
    testing.expectEqual(.{ .constant = 100 }, instruction.y);
    testing.expectEqual(.default, instruction.scale);
}

test "parse parses instruction with default scale/animation source and consumes 4 extra bytes" {
    const instruction = try expectParse(parse, &BytecodeExamples.default_scale_from_animations, 4);

    testing.expectEqual(.animations, instruction.source);
    testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    testing.expectEqual(.{ .constant = 160 }, instruction.x);
    testing.expectEqual(.{ .constant = 100 }, instruction.y);
    testing.expectEqual(.default, instruction.scale);
}

test "execute with constants calls drawPolygon with correct parameters" {
    const instruction = Instance{
        .source = .animations,
        .address = 0xDEAD,
        .x = .{ .constant = 320 },
        .y = .{ .constant = 200 },
        .scale = .default,
    };

    var machine = MockMachine.new(struct {
        pub fn drawPolygon(source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: ?Video.PolygonScale) !void {
            testing.expectEqual(.animations, source);
            testing.expectEqual(0xDEAD, address);
            testing.expectEqual(320, point.x);
            testing.expectEqual(200, point.y);
            testing.expectEqual(null, scale);
        }
    });

    try instruction._execute(&machine);

    testing.expectEqual(1, machine.call_counts.drawPolygon);
}

test "execute with registers calls drawPolygon with correct parameters" {
    const instruction = Instance{
        .source = .polygons,
        .address = 0xDEAD,
        .x = .{ .register = 1 },
        .y = .{ .register = 2 },
        .scale = .{ .register = 3 },
    };

    var machine = MockMachine.new(struct {
        pub fn drawPolygon(source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: ?Video.PolygonScale) !void {
            testing.expectEqual(.polygons, source);
            testing.expectEqual(0xDEAD, address);
            testing.expectEqual(-1234, point.x);
            testing.expectEqual(5678, point.y);
            testing.expectEqual(128, scale);
        }
    });

    machine.registers[1] = -1234;
    machine.registers[2] = 5678;
    machine.registers[3] = 128;

    try instruction._execute(&machine);

    testing.expectEqual(1, machine.call_counts.drawPolygon);
}

test "execute with register scale value truncates out-of-range scale" {
    const instruction = Instance{
        .source = .polygons,
        .address = 0xDEAD,
        .x = .{ .constant = 320 },
        .y = .{ .constant = 200 },
        .scale = .{ .register = 1 },
    };

    var machine = MockMachine.new(struct {
        pub fn drawPolygon(_source: Video.PolygonSource, _address: Video.PolygonAddress, _point: Point.Instance, scale: ?Video.PolygonScale) !void {
            testing.expectEqual(0b0010_1011, scale);
        }
    });

    // -18901 = 0b1011_0110_0010_1011 in two's-complement;
    // top 8 bits should get truncated
    machine.registers[1] = -18901;

    try instruction._execute(&machine);

    testing.expectEqual(1, machine.call_counts.drawPolygon);
}
