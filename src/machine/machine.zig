const ThreadID = @import("../values/thread_id.zig");
const BufferID = @import("../values/buffer_id.zig");
const ResourceID = @import("../values/resource_id.zig");
const StringID = @import("../values/string_id.zig");
const PaletteID = @import("../values/palette_id.zig");
const ColorID = @import("../values/color_id.zig");
const Channel = @import("../values/channel.zig");
const Point = @import("../values/point.zig");
const PolygonScale = @import("../values/polygon_scale.zig");
const RegisterID = @import("../values/register_id.zig");
const Register = @import("../values/register.zig");
const GamePart = @import("../values/game_part.zig");

const Thread = @import("thread.zig");
const Stack = @import("stack.zig");
const Registers = @import("registers.zig");
const Program = @import("program.zig");
const Video = @import("video.zig");
const Audio = @import("audio.zig");
const Memory = @import("memory.zig");
const Host = @import("host.zig");
const UserInput = @import("user_input.zig");

const Reader = @import("../resources/reader.zig");

const static_limits = @import("../static_limits.zig");

const mem = @import("std").mem;
const fs = @import("std").fs;

const log_unimplemented = @import("../utils/logging.zig").log_unimplemented;

const thread_count = static_limits.thread_count;
pub const Threads = [thread_count]Thread.Instance;

pub const Instance = struct {
    /// The current state of the VM's 64 threads.
    threads: Threads,

    /// The current state of the VM's 256 registers.
    registers: Registers.Instance,

    /// The current program execution stack.
    stack: Stack.Instance,

    /// The currently-running program.
    program: Program.Instance,

    /// The current state of the video subsystem.
    video: Video.Instance,

    /// The current state of resources loaded into memory.
    memory: Memory.Instance,

    /// The host which the machine will send video and audio output to and read player input from.
    host: Host.Interface,

    /// The currently-active game part.
    current_game_part: GamePart.Enum,

    /// The next game part that has been scheduled to be started by a program instruction.
    /// Null if no game part is scheduled.
    scheduled_game_part: ?GamePart.Enum = null,

    const Self = @This();

    // -- Virtual machine lifecycle --

    /// Create a new virtual machine that uses the specified allocator to allocate memory
    /// and reads game data from the specified reader. The virtual machine will attempt
    /// to load the resources for the specified game part.
    /// On success, returns a machine instance that is ready to simulate.
    fn init(allocator: mem.Allocator, reader: Reader.Interface, host: Host.Interface, initial_game_part: GamePart.Enum, random_seed: Register.Unsigned) !Self {
        var memory = try Memory.new(allocator, reader);
        errdefer memory.deinit();

        var self = Self{
            .threads = .{.{}} ** thread_count,
            .registers = .{},
            .stack = .{},
            .memory = memory,
            .host = host,
            // The video and program will be populated once the first game part is loaded.
            // TODO: the machine shouldn't know which fields of the Video instance need to be marked undefined.
            .video = .{
                .polygons = undefined,
                .animations = undefined,
                .palettes = undefined,
            },
            .program = undefined,
            .current_game_part = undefined,
        };

        // Initialize registers to their expected values.
        // Copypasta from reference implementation:
        // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/vm.cpp#L37
        self.registers.setUnsigned(.virtual_machine_startup_UNKNOWN, 0x81);
        self.registers.setUnsigned(.random_seed, random_seed);

        // Load the resources for the initial game part.
        // This will populate the previously `undefined` program and video struct.
        try self.startGamePart(initial_game_part);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.memory.deinit();
        self.* = undefined;
    }

    pub fn applyUserInput(self: *Self, input: UserInput.Instance) void {
        const register_values = input.registerValues();

        self.registers.setSigned(.left_right_input, register_values.left_right_input);
        self.registers.setSigned(.up_down_input, register_values.up_down_input);
        self.registers.setSigned(.up_down_input_2, register_values.up_down_input);
        self.registers.setSigned(.action_input, register_values.action_input);
        self.registers.setBitPattern(.movement_inputs, register_values.movement_inputs);
        self.registers.setBitPattern(.all_inputs, register_values.all_inputs);

        // TODO: check if the `last_pressed_character` register is read by any other game part;
        // we may be able to unconditionally set it.
        if (self.current_game_part == .password_entry) {
            self.registers.setUnsigned(.last_pressed_character, register_values.last_pressed_character);
        }

        if (input.show_password_screen and self.current_game_part.allowsPasswordEntry()) {
            self.scheduled_game_part = .password_entry;
        }
    }

    /// Immediately unload all resources, load the resources for the specified game part,
    /// and prepare to execute its bytecode.
    /// Returns an error if one or more resources do not exist or could not be loaded.
    /// Not intended to be called outside of execution: instead call `scheduleGamePart`,
    /// which will let the current game cycle finish executing before beginning the new
    /// game part on the next run loop.
    fn startGamePart(self: *Self, game_part: GamePart.Enum) !void {
        const resource_locations = try self.memory.loadGamePart(game_part);
        self.program = Program.new(resource_locations.bytecode);
        self.video.setResourceLocations(resource_locations.palettes, resource_locations.polygons, resource_locations.animations);

        // Stop all threads and reset the main thread to begin execution at the start of the current program
        for (self.threads) |*thread| {
            thread.execution_state = .inactive;
        }
        self.threads[ThreadID.main].execution_state = .{ .active = 0 };

        self.current_game_part = game_part;
        self.scheduled_game_part = null;
    }

    // -- Resource subsystem interface --

    /// Schedule the specified game part to begin on the next run loop.
    pub fn scheduleGamePart(self: *Self, game_part: GamePart.Enum) void {
        self.scheduled_game_part = game_part;
    }

    /// Load the specified resource if it is not already loaded.
    /// Returns an error if the specified resource ID does not exist or could not be loaded.
    pub fn loadResource(self: *Self, resource_id: ResourceID.Raw) !void {
        const location = try self.memory.loadIndividualResource(resource_id);

        switch (location) {
            // Bitmap resources must be loaded immediately from their temporary location into the video buffer.
            .temporary_bitmap => |address| try self.video.loadBitmapResource(address),
            // Audio resources will remain in memory for a later instruction to play them.
            .audio => {},
        }
    }

    /// Unload all audio resources and stop any currently-playing sound.
    pub fn unloadAllResources(self: *Self) void {
        self.memory.unloadAllIndividualResources();
        // TODO: the reference implementation mentioned that this will also stop any playing sound,
        // this function may need to tell the audio subsystem (once we have one) to do that manually.
    }

    // -- Video subsystem interface --

    /// Render a polygon from the specified source and address at the specified screen position and scale.
    /// Returns an error if the specified polygon address was invalid.
    pub fn drawPolygon(self: *Self, source: Video.PolygonSource, address: Video.PolygonAddress, point: Point.Instance, scale: PolygonScale.Raw) !void {
        try self.video.drawPolygon(source, address, point, scale);
    }

    /// Render a string from the current string table at the specified screen position in the specified color.
    /// Returns an error if the string could not be found.
    pub fn drawString(self: *Self, string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point.Instance) !void {
        try self.video.drawString(string_id, color_id, point);
    }

    /// Select the active palette to render the video buffer in.
    pub fn selectPalette(self: *Self, palette_id: PaletteID.Trusted) !void {
        try self.video.selectPalette(palette_id);
    }

    /// Select the video buffer that subsequent drawPolygon and drawString operations will draw into.
    pub fn selectVideoBuffer(self: *Self, buffer_id: BufferID.Enum) void {
        self.video.selectBuffer(buffer_id);
    }

    /// Fill a specified video buffer with a single color.
    pub fn fillVideoBuffer(self: *Self, buffer_id: BufferID.Enum, color_id: ColorID.Trusted) void {
        self.video.fillBuffer(buffer_id, color_id);
    }

    /// Copy the contents of one video buffer into another at the specified vertical offset.
    pub fn copyVideoBuffer(self: *Self, source: BufferID.Enum, destination: BufferID.Enum, vertical_offset: Point.Coordinate) void {
        self.video.copyBuffer(source, destination, vertical_offset);
    }

    /// Render the contents of the specified buffer to the host screen after the specified delay.
    pub fn renderVideoBuffer(self: *Self, buffer_id: BufferID.Enum, delay: Video.Milliseconds) void {
        self.video.renderBuffer(buffer_id, delay, self.host);
    }

    // -- Audio subsystem interface --

    /// Start playing a music track from a specified resource.
    /// Returns an error if the resource does not exist or could not be loaded.
    pub fn playMusic(_: *Self, resource_id: ResourceID.Raw, offset: Audio.Offset, delay: Audio.Delay) !void {
        log_unimplemented("Audio.playMusic: play #{X} at offset {} after delay {}", .{
            resource_id,
            offset,
            delay,
        });
    }

    /// Set on the current or subsequent music track.
    pub fn setMusicDelay(_: *Self, delay: Audio.Delay) void {
        log_unimplemented("Audio.setMusicDelay: set delay to {}", .{delay});
    }

    /// Stop playing any current music track.
    pub fn stopMusic(_: *Self) void {
        log_unimplemented("Audio.stopMusic: stop playing", .{});
    }

    /// Play a sound effect from the specified resource on the specified channel.
    /// Returns an error if the resource does not exist or could not be loaded.
    pub fn playSound(_: *Self, resource_id: ResourceID.Raw, channel: Channel.Trusted, volume: Audio.Volume, frequency: Audio.Frequency) !void {
        log_unimplemented("Audio.playSound: play #{X} on channel {} at volume {}, frequency {}", .{
            resource_id,
            channel,
            volume,
            frequency,
        });
    }

    /// Stop any sound effect playing on the specified channel.
    pub fn stopChannel(_: *Self, channel: Channel.Trusted) void {
        log_unimplemented("Audio.stopChannel: stop playing on channel {}", .{channel});
    }
};

pub fn new(allocator: mem.Allocator, reader: Reader.Interface, host: Host.Interface, initial_game_part: GamePart.Enum, random_seed: Register.Unsigned) !Instance {
    return Instance.init(allocator, reader, host, initial_game_part, random_seed);
}

const MockRepository = @import("../resources/mock_repository.zig");
const MockHost = @import("test_helpers/mock_host.zig");

/// Returns a machine instance suitable for use in tests.
/// The machine will load game data from a fake repository,
/// and will be optionally be initialized with the specified bytecode program.
///
/// Usage:
/// ------
/// const machine = Machine.testInstance();
/// defer machine.deinit();
/// try testing.expectEqual(result, do_something_that_requires_a_machine(machine));
pub fn testInstance(possible_bytecode: ?[]const u8) Instance {
    var machine = new(testing.allocator, MockRepository.test_reader, MockHost.test_host, .intro_cinematic, 0) catch unreachable;
    if (possible_bytecode) |bytecode| {
        machine.program = Program.new(bytecode);
    }
    return machine;
}

// -- Tests --

const testing = @import("../utils/testing.zig");
const meta = @import("std").meta;

test "new creates virtual machine instance with expected initial state" {
    const initial_game_part = GamePart.Enum.gameplay1;
    const random_seed = 12345;

    var machine = try new(testing.allocator, MockRepository.test_reader, MockHost.test_host, initial_game_part, random_seed);
    defer machine.deinit();

    for (machine.threads) |thread, id| {
        if (id == ThreadID.main) {
            try testing.expectEqual(.{ .active = 0 }, thread.execution_state);
        } else {
            try testing.expectEqual(.inactive, thread.execution_state);
        }
        try testing.expectEqual(.running, thread.pause_state);
    }

    for (machine.registers.unsignedSlice()) |register, id| {
        const expected_value: Register.Unsigned = switch (@intToEnum(RegisterID.Enum, id)) {
            .virtual_machine_startup_UNKNOWN => 0x81,
            .random_seed => random_seed,
            else => 0,
        };
        try testing.expectEqual(expected_value, register);
    }

    try testing.expectEqual(null, machine.scheduled_game_part);

    // Ensure each resource was loaded for the requested game part
    // and passed to the program and video subsystems
    const resource_ids = initial_game_part.resourceIDs();

    const bytecode_address = try machine.memory.resourceLocation(resource_ids.bytecode);
    try testing.expect(bytecode_address != null);
    try testing.expectEqual(bytecode_address.?, machine.program.bytecode);

    const palettes_address = try machine.memory.resourceLocation(resource_ids.palettes);
    try testing.expect(palettes_address != null);
    try testing.expectEqual(palettes_address.?, machine.video.palettes.data);

    const polygons_address = try machine.memory.resourceLocation(resource_ids.polygons);
    try testing.expect(polygons_address != null);
    try testing.expectEqual(polygons_address.?, machine.video.polygons.data);

    const animations_address = try machine.memory.resourceLocation(resource_ids.animations.?);
    try testing.expect(animations_address != null);
    try testing.expect(machine.video.animations != null);
    try testing.expectEqual(animations_address.?, machine.video.animations.?.data);
}

test "scheduleGamePart schedules a new game part without loading it" {
    var machine = try new(testing.allocator, MockRepository.test_reader, MockHost.test_host, .copy_protection, 0);
    defer machine.deinit();

    try testing.expectEqual(null, machine.scheduled_game_part);

    const next_game_part = GamePart.Enum.intro_cinematic;
    const resource_ids = next_game_part.resourceIDs();

    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.bytecode));
    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.palettes));
    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.polygons));

    machine.scheduleGamePart(next_game_part);
    try testing.expectEqual(next_game_part, machine.scheduled_game_part);

    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.bytecode));
    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.palettes));
    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.polygons));
}

// - LoadResource tests -

test "loadResource loads audio resource into main memory" {
    var machine = testInstance(null);
    defer machine.deinit();

    const audio_resource_id = MockRepository.Fixtures.sfx_resource_id;

    try testing.expectEqual(null, try machine.memory.resourceLocation(audio_resource_id));
    try machine.loadResource(audio_resource_id);
    try testing.expect((try machine.memory.resourceLocation(audio_resource_id)) != null);
}

test "loadResource copies bitmap resource directly into video buffer without persisting in main memory" {
    var machine = testInstance(null);
    defer machine.deinit();

    const buffer = &machine.video.buffers[Video.Instance.bitmap_buffer_id];
    buffer.fill(0x0);
    const original_buffer_contents = buffer.toBitmap();

    const bitmap_resource_id = MockRepository.Fixtures.bitmap_resource_id;
    try testing.expectEqual(null, machine.memory.resourceLocation(bitmap_resource_id));
    try machine.loadResource(bitmap_resource_id);
    try testing.expectEqual(null, machine.memory.resourceLocation(bitmap_resource_id));

    const new_buffer_contents = buffer.toBitmap();
    // The fake bitmap resource data should have been filled with a 0b01010 bit pattern,
    // which should never be equal to the flat black color filled into the buffer.
    try testing.expect(meta.eql(original_buffer_contents, new_buffer_contents) == false);
}

test "loadResource returns error on invalid resource ID" {
    var machine = testInstance(null);
    defer machine.deinit();

    const invalid_id = MockRepository.Fixtures.invalid_resource_id;
    try testing.expectError(error.InvalidResourceID, machine.loadResource(invalid_id));
}

// - applyUserInput tests -

test "applyUserInput sets expected register values" {
    var machine = testInstance(null);
    defer machine.deinit();

    const full_input = UserInput.Instance{
        .action = true,
        .left = true,
        .right = true,
        .up = true,
        .down = true,
    };

    machine.applyUserInput(full_input);

    try testing.expectEqual(1, machine.registers.signed(.action_input));
    try testing.expectEqual(-1, machine.registers.signed(.left_right_input));
    try testing.expectEqual(-1, machine.registers.signed(.up_down_input));
    try testing.expectEqual(-1, machine.registers.signed(.up_down_input_2));
    try testing.expectEqual(0b1111, machine.registers.bitPattern(.movement_inputs));
    try testing.expectEqual(0b1000_1111, machine.registers.bitPattern(.all_inputs));

    const empty_input = UserInput.Instance{};
    machine.applyUserInput(empty_input);

    try testing.expectEqual(0, machine.registers.signed(.action_input));
    try testing.expectEqual(0, machine.registers.signed(.left_right_input));
    try testing.expectEqual(0, machine.registers.signed(.up_down_input));
    try testing.expectEqual(0, machine.registers.signed(.up_down_input_2));
    try testing.expectEqual(0b0000, machine.registers.bitPattern(.movement_inputs));
    try testing.expectEqual(0b0000_0000, machine.registers.bitPattern(.all_inputs));
}

test "applyUserInput sets RegisterID.last_pressed_character when in password entry screen" {
    var machine = testInstance(null);
    defer machine.deinit();

    try machine.startGamePart(.password_entry);

    const original_value = 1234;
    machine.registers.setUnsigned(.last_pressed_character, original_value);

    const input = UserInput.Instance{ .last_pressed_character = 'a' };
    machine.applyUserInput(input);

    try testing.expectEqual('A', machine.registers.unsigned(.last_pressed_character));
}

test "applyUserInput does not touch RegisterID.last_pressed_character during other game parts" {
    var machine = testInstance(null);
    defer machine.deinit();

    try testing.expect(machine.current_game_part != .password_entry);

    const original_value = 1234;
    machine.registers.setUnsigned(.last_pressed_character, original_value);

    const input = UserInput.Instance{ .last_pressed_character = 'a' };
    machine.applyUserInput(input);

    try testing.expectEqual(original_value, machine.registers.unsigned(.last_pressed_character));
}

test "applyUserInput opens password screen if permitted for current game part" {
    var machine = testInstance(null);
    defer machine.deinit();

    try testing.expectEqual(.intro_cinematic, machine.current_game_part);

    const input = UserInput.Instance{ .show_password_screen = true };
    machine.applyUserInput(input);

    try testing.expectEqual(.password_entry, machine.scheduled_game_part);
}

test "applyUserInput does not open password screen when in copy protection" {
    var machine = testInstance(null);
    defer machine.deinit();

    try machine.startGamePart(.copy_protection);

    const input = UserInput.Instance{ .show_password_screen = true };
    machine.applyUserInput(input);

    try testing.expectEqual(null, machine.scheduled_game_part);
}

test "applyUserInput does not open password screen when already in password screen" {
    var machine = testInstance(null);
    defer machine.deinit();

    try machine.startGamePart(.password_entry);

    const input = UserInput.Instance{ .show_password_screen = true };
    machine.applyUserInput(input);

    try testing.expectEqual(null, machine.scheduled_game_part);
}
