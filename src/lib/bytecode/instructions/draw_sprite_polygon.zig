const anotherworld = @import("../../anotherworld.zig");
const rendering = anotherworld.rendering;
const vm = anotherworld.vm;

const Point = rendering.Point;
const PolygonScale = rendering.PolygonScale;

const Opcode = @import("../opcode.zig").Opcode;
const Program = vm.Program;
const Machine = vm.Machine;
const RegisterID = vm.RegisterID;

/// Draw a polygon at a location and zoom level that are either hardcoded constants
/// or dynamic values read from registers.
pub const DrawSpritePolygon = struct {
    /// The source location from which to read polygon data.
    source: vm.PolygonSource,

    /// The address within the polygon source from which to read polygon data.
    address: rendering.PolygonResource.Address,

    /// The source for the X offset at which to draw the polygon.
    x: union(enum) {
        constant: Point.Coordinate,
        register: RegisterID,
    },

    /// The source for the Y offset at which to draw the polygon.
    y: union(enum) {
        constant: Point.Coordinate,
        register: RegisterID,
    },

    /// The source for the scale at which to draw the polygon.
    scale: union(enum) {
        default,
        constant: PolygonScale,
        register: RegisterID,
    },

    const Self = @This();

    /// Parse the next instruction from a bytecode program.
    /// Consumes 5-8 bytes from the bytecode on success, including the opcode.
    /// Returns an error if the bytecode could not be read or contained an invalid instruction.
    pub fn parse(raw_opcode: Opcode.Raw, program: *Program) ParseError!Self {
        var self: Self = undefined;

        // Unlike DrawBackgroundPolygon, which treats the lower 7 bits of the opcode as the top part
        // of the polygon address, this operation reads the two bytes after the opcode as the polygon
        // address and uses the lower 6 bits of the opcode for other parts of the instruction (see below.)
        // It interprets the raw polygon address the same way as DrawBackgroundPolygon though,
        // right-shifting by one to land on an even address boundary.
        const raw_address = try program.read(rendering.PolygonResource.Address);
        self.address = raw_address << 1;

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
        // - `ss` controls where to read the scale from and which resource to read polygon data from:
        //   - 00: use `.polygons` resource, set default scale
        //   - 01: use `.polygons` resource, read next byte as ID of register containing scale
        //   - 10: use `.polygons` resource, read next byte as unsigned 8-bit constant
        //   - 11: use `.animations` resource, set default scale

        const raw_x = @truncate(u2, raw_opcode >> 4);
        const raw_y = @truncate(u2, raw_opcode >> 2);
        const raw_scale = @truncate(u2, raw_opcode);

        self.x = switch (raw_x) {
            0b00 => .{ .constant = try program.read(Point.Coordinate) },
            0b01 => .{ .register = RegisterID.cast(try program.read(RegisterID.Raw)) },
            0b10 => .{ .constant = @as(Point.Coordinate, try program.read(u8)) },
            0b11 => .{ .constant = @as(Point.Coordinate, try program.read(u8)) + 256 },
        };

        self.y = switch (raw_y) {
            0b00 => .{ .constant = try program.read(Point.Coordinate) },
            0b01 => .{ .register = RegisterID.cast(try program.read(RegisterID.Raw)) },
            0b10, 0b11 => .{ .constant = @as(Point.Coordinate, try program.read(u8)) },
        };

        switch (raw_scale) {
            0b00 => {
                self.source = .polygons;
                self.scale = .default;
            },
            0b01 => {
                self.source = .polygons;
                self.scale = .{ .register = RegisterID.cast(try program.read(RegisterID.Raw)) };
            },
            0b10 => {
                self.source = .polygons;
                self.scale = .{ .constant = PolygonScale.cast(try program.read(u8)) };
            },
            0b11 => {
                self.source = .animations;
                self.scale = .default;
            },
        }

        return self;
    }

    // Public implementation is constrained to concrete type so that instruction.zig can infer errors.
    pub fn execute(self: Self, machine: *Machine) !void {
        return self._execute(machine);
    }

    // Private implementation is generic to allow tests to use mocks.
    fn _execute(self: Self, machine: anytype) !void {
        const x = switch (self.x) {
            .constant => |constant| constant,
            .register => |id| machine.registers.signed(id),
        };
        const y = switch (self.y) {
            .constant => |constant| constant,
            .register => |id| machine.registers.signed(id),
        };
        const scale = switch (self.scale) {
            .constant => |constant| constant,
            .register => |id| PolygonScale.cast(machine.registers.unsigned(id)),
            .default => .default,
        };

        try machine.drawPolygon(self.source, self.address, .{ .x = x, .y = y }, scale);
    }

    // - Exported constants -

    pub const opcode = Opcode.DrawSpritePolygon;
    pub const ParseError = Program.ReadError;

    // -- Bytecode examples --

    // zig fmt: off
    pub const Fixtures = struct {
        /// Example bytecode that should produce a valid instruction.
        pub const valid = wide_constants;

        const registers = [6]u8{
            0b01_01_01_01,              // opcode
            0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
            1, 2, 3,                    // register IDs for x, y and scale
        };

        const wide_constants = [8]u8{
            0b01_00_00_10,              // opcode
            0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
            0b1011_0110, 0b0010_1011,   // x constant (-18901 in two's-complement)
            0b0000_1101, 0b1000_1110,   // y constant (+3470 in two's-complement)
            255,                        // scale
        };

        const short_constants = [6]u8{
            0b01_10_10_10,              // opcode
            0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
            160, 100,                   // constants for x and y
            255,                        // scale
        };

        const short_boosted_x_constants = [6]u8{
            0b01_11_10_10,              // opcode
            0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
            64, 200,                    // constants for x + 256 and y
            255,                        // scale
        };

        const default_scale_from_polygons = [5]u8{
            0b01_10_10_00,              // opcode
            0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
            160, 100,                   // constants for x and y
        };

        const default_scale_from_animations = [5]u8{
            0b01_10_10_11,              // opcode
            0b0000_1111, 0b0000_1111,   // address (will be right-shifted by 1)
            160, 100,                   // constants for x and y
        };
    };
    // zig fmt: on
};

// -- Tests --

const testing = @import("utils").testing;
const expectParse = @import("test_helpers/parse.zig").expectParse;
const mockMachine = vm.mockMachine;

test "parse parses all-registers instruction and consumes 6 bytes" {
    const instruction = try expectParse(DrawSpritePolygon.parse, &DrawSpritePolygon.Fixtures.registers, 6);

    try testing.expectEqual(.polygons, instruction.source);
    // Address is right-shifted by 1
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .register = RegisterID.cast(1) }, instruction.x);
    try testing.expectEqual(.{ .register = RegisterID.cast(2) }, instruction.y);
    try testing.expectEqual(.{ .register = RegisterID.cast(3) }, instruction.scale);
}

test "parse parses instruction with full-width constants and consumes 8 bytes" {
    const instruction = try expectParse(DrawSpritePolygon.parse, &DrawSpritePolygon.Fixtures.wide_constants, 8);

    try testing.expectEqual(.polygons, instruction.source);
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .constant = -18901 }, instruction.x);
    try testing.expectEqual(.{ .constant = 3470 }, instruction.y);
    try testing.expectEqual(.{ .constant = PolygonScale.cast(255) }, instruction.scale);
}

test "parse parses instruction with short constants and consumes 6 bytes" {
    const instruction = try expectParse(DrawSpritePolygon.parse, &DrawSpritePolygon.Fixtures.short_constants, 6);

    try testing.expectEqual(.polygons, instruction.source);
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .constant = 160 }, instruction.x);
    try testing.expectEqual(.{ .constant = 100 }, instruction.y);
    try testing.expectEqual(.{ .constant = PolygonScale.cast(255) }, instruction.scale);
}

test "parse parses instruction with short constants with boosted X and consumes 6 bytes" {
    const instruction = try expectParse(DrawSpritePolygon.parse, &DrawSpritePolygon.Fixtures.short_boosted_x_constants, 6);

    try testing.expectEqual(.polygons, instruction.source);
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .constant = 64 + 256 }, instruction.x);
    try testing.expectEqual(.{ .constant = 200 }, instruction.y);
    try testing.expectEqual(.{ .constant = PolygonScale.cast(255) }, instruction.scale);
}

test "parse parses instruction with default scale/polygon source and consumes 5 bytes" {
    const instruction = try expectParse(DrawSpritePolygon.parse, &DrawSpritePolygon.Fixtures.default_scale_from_polygons, 5);

    try testing.expectEqual(.polygons, instruction.source);
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .constant = 160 }, instruction.x);
    try testing.expectEqual(.{ .constant = 100 }, instruction.y);
    try testing.expectEqual(.default, instruction.scale);
}

test "parse parses instruction with default scale/animation source and consumes 5 bytes" {
    const instruction = try expectParse(DrawSpritePolygon.parse, &DrawSpritePolygon.Fixtures.default_scale_from_animations, 5);

    try testing.expectEqual(.animations, instruction.source);
    try testing.expectEqual(0b0001_1110_0001_1110, instruction.address);
    try testing.expectEqual(.{ .constant = 160 }, instruction.x);
    try testing.expectEqual(.{ .constant = 100 }, instruction.y);
    try testing.expectEqual(.default, instruction.scale);
}

test "execute with constants calls drawPolygon with correct parameters" {
    const instruction = DrawSpritePolygon{
        .source = .animations,
        .address = 0xDEAD,
        .x = .{ .constant = 320 },
        .y = .{ .constant = 200 },
        .scale = .default,
    };

    var machine = mockMachine(struct {
        pub fn drawPolygon(source: vm.PolygonSource, address: rendering.PolygonResource.Address, point: Point, scale: PolygonScale) !void {
            try testing.expectEqual(.animations, source);
            try testing.expectEqual(0xDEAD, address);
            try testing.expectEqual(320, point.x);
            try testing.expectEqual(200, point.y);
            try testing.expectEqual(.default, scale);
        }
    });

    try instruction._execute(&machine);

    try testing.expectEqual(1, machine.call_counts.drawPolygon);
}

test "execute with registers calls drawPolygon with correct parameters" {
    const x_register = RegisterID.cast(1);
    const y_register = RegisterID.cast(2);
    const scale_register = RegisterID.cast(3);

    const instruction = DrawSpritePolygon{
        .source = .polygons,
        .address = 0xDEAD,
        .x = .{ .register = x_register },
        .y = .{ .register = y_register },
        .scale = .{ .register = scale_register },
    };

    var machine = mockMachine(struct {
        pub fn drawPolygon(source: vm.PolygonSource, address: rendering.PolygonResource.Address, point: Point, scale: PolygonScale) !void {
            try testing.expectEqual(.polygons, source);
            try testing.expectEqual(0xDEAD, address);
            try testing.expectEqual(-1234, point.x);
            try testing.expectEqual(5678, point.y);
            try testing.expectEqual(PolygonScale.cast(16384), scale);
        }
    });

    machine.registers.setSigned(x_register, -1234);
    machine.registers.setSigned(y_register, 5678);
    machine.registers.setSigned(scale_register, 16384);

    try instruction._execute(&machine);

    try testing.expectEqual(1, machine.call_counts.drawPolygon);
}

test "execute with register scale value interprets value as unsigned" {
    const scale_register = RegisterID.cast(1);

    const instruction = DrawSpritePolygon{
        .source = .polygons,
        .address = 0xDEAD,
        .x = .{ .constant = 320 },
        .y = .{ .constant = 200 },
        .scale = .{ .register = scale_register },
    };

    var machine = mockMachine(struct {
        pub fn drawPolygon(_: vm.PolygonSource, _: rendering.PolygonResource.Address, _: Point, scale: PolygonScale) !void {
            try testing.expectEqual(PolygonScale.cast(46635), scale);
        }
    });

    // 0b1011_0110_0010_1011 = -18901 in signed two's-complement;
    // Should be interpreted as 46635 when unsigned
    machine.registers.setSigned(scale_register, -18901);

    try instruction._execute(&machine);

    try testing.expectEqual(1, machine.call_counts.drawPolygon);
}
