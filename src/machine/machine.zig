//! Represents a virtual machine that loads and executes Another World game data.
//!
//! The virtual machine comprises several pieces of state:
//! - The program for the currently-loaded part of the game.
//! - A bank of 256 "registers", used to track game state and player input.
//! - A list of 64 "threads", which each execute their own block of the current program
//!   and then yield control to the next active thread.
//! - A list of the memory addresses of each currently-loaded resource
//!   (polygon data, audio and bytecode).
//! - A set of 4 320x200x16 video buffers that the game draws polygons and fonts into.
//! - Sundry state like the currently-loaded palette, active draw buffer, subroutine stack,
//!   and next game part to load.
//!
//! (See https://fabiensanglard.net/anotherWorld_code_review/index.php for a detailed exploration
//! of this architecture.)
//!
//! The virtual machine does not know how to interact with the host operating system directly.
//! Instead, a host process is expected to:
//! - create a window or rendering surface in the host OS to display video output,
//! - manage an event loop in the host OS to process user input,
//! - provide a reader for a source of binary game data (e.g. a filesystem directory),
//! - create a new virtual machine, and finally
//! - run the virtual machine's runTic function in a loop until the player exits the game.
//!
//! On each game tic, the virtual machine will produce zero or more frames of video output,
//! notifying the host process that each new frame is ready via a callback function: see `host.zig`.
//! Each frame has a delay determining how long the previous frame should be left on-screen:
//! the host is expected to sleep for that long before allowing execution to continue, which indirectly
//! decides the framerate of the game.

const ThreadID = @import("../values/thread_id.zig");
const BufferID = @import("../values/buffer_id.zig").BufferID;
const ResourceID = @import("../values/resource_id.zig").ResourceID;
const StringID = @import("../values/string_id.zig");
const PaletteID = @import("../values/palette_id.zig");
const ColorID = @import("../values/color_id.zig");
const Channel = @import("../values/channel.zig");
const Point = @import("../values/point.zig").Point;
const PolygonScale = @import("../values/polygon_scale.zig");
const RegisterID = @import("../values/register_id.zig").RegisterID;
const Register = @import("../values/register.zig");
const GamePart = @import("../values/game_part.zig").GamePart;

const Thread = @import("thread.zig").Thread;
const Stack = @import("stack.zig").Stack;
const Registers = @import("registers.zig").Registers;
const Program = @import("program.zig").Program;
const Video = @import("video.zig").Video;
const Audio = @import("audio.zig").Audio;
const Memory = @import("memory.zig").Memory;
const Host = @import("host.zig").Host;
const UserInput = @import("user_input.zig").UserInput;

const ResourceReader = @import("../resources/resource_reader.zig").ResourceReader;
const MockRepository = @import("../resources/mock_repository.zig").MockRepository;
const mock_host = @import("test_helpers/mock_host.zig");

const static_limits = @import("../static_limits.zig");

const std = @import("std");
const mem = std.mem;

const log = @import("../utils/logging.zig").log;

const thread_count = static_limits.thread_count;

pub const Machine = struct {
    /// The current state of the VM's 64 threads.
    threads: [thread_count]Thread,

    /// The current state of the VM's 256 registers.
    registers: Registers,

    /// The current program execution stack.
    stack: Stack,

    /// The currently-running program.
    program: Program,

    /// The current state of the video subsystem.
    video: Video,

    /// The current state of resources loaded into memory.
    memory: Memory,

    /// The host which the machine will send video and audio output to.
    host: Host,

    /// The currently-active game part.
    current_game_part: GamePart,

    /// The game part that has been scheduled to start on the next game tic.
    /// Null if no game part is scheduled.
    scheduled_game_part: ?GamePart = null,

    const Self = @This();

    // - Virtual machine lifecycle -
    // The methods below are intended to be called by the host.

    /// Create a new virtual machine that uses the specified allocator to allocate memory,
    /// reads game data from the specified reader, and sends video and audio output to the specified host.
    /// At startup, the virtual machine will attempt to load the resources for the initial game part.
    /// On success, returns a machine instance that is ready to begin simulating.
    pub fn init(allocator: mem.Allocator, reader: ResourceReader, host: Host, options: Options) !Self {
        var memory = try Memory.init(allocator, reader);
        errdefer memory.deinit();

        var self = Self{
            .threads = .{.{}} ** thread_count,
            .registers = .{},
            .stack = .{},
            .memory = memory,
            .host = host,
            // The video and program will be populated once the first game part is loaded at the end of this function.
            // FIXME: the machine shouldn't know which fields of the Video instance need to be marked undefined.
            .video = .{
                .polygons = undefined,
                .animations = undefined,
                .palettes = undefined,
            },
            .program = undefined,
            .current_game_part = undefined,
        };

        const seed = options.seed orelse @truncate(Register.Signed, std.time.milliTimestamp());
        // Initialize registers to their expected values.
        self.registers.setSigned(.random_seed, seed);

        // This list of copy protection bypass values is incomplete:
        // Some sections of the game will work, but other sections will still
        // soft-lock unless the user has gone completed copy protection.
        self.registers.setUnsigned(.virtual_machine_startup_UNKNOWN, 0x0081);
        self.registers.setUnsigned(.copy_protection_bypass_1, 0b0001_0000); // Bit 4 needs to be set, other bits aren't checked
        self.registers.setUnsigned(.copy_protection_bypass_2, 0x0080); // Doesn't seem to be checked by the 1st gameplay sequence
        self.registers.setUnsigned(.copy_protection_bypass_3, 0x0021);
        self.registers.setUnsigned(.copy_protection_bypass_4, 0x0FA0);

        // Load the resources for the initial game part.
        // This will populate the previously `undefined` program and video struct.
        try self.startGamePart(options.initial_game_part);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.memory.deinit();
        self.* = undefined;
    }

    /// Run the virtual machine for a single game tic.
    /// This will:
    /// 1. load a new game part if one was scheduled on the previous tic;
    /// 2. apply the specified user input to the state of the VM;
    /// 3. apply any thread state changes that were scheduled on the previous tic;
    /// 4. run every thread using the bytecode for the current game part.
    pub fn runTic(self: *Self, input: UserInput) !void {
        if (self.scheduled_game_part) |game_part| {
            try self.startGamePart(game_part);
        }

        // Apply user input only after loading any scheduled game part, as certain inputs
        // are only handled when running the password entry game part.
        self.applyUserInput(input);

        // All threads must be updated to apply any requested pause, resume etc. state changes
        // *before* we start running the current tic, because the program may schedule new states
        // this tic that should not be applied until next tic.
        for (self.threads) |*thread| {
            thread.applyScheduledStates();
        }

        for (self.threads) |*thread| {
            try thread.run(self, static_limits.max_instructions_per_tic);
        }
    }

    // - System calls -
    // The methods below are only intended to be called by bytecode instructions.

    // -- Resource subsystem interface --

    /// Schedule the specified game part to begin on the next run loop.
    pub fn scheduleGamePart(self: *Self, game_part: GamePart) void {
        self.scheduled_game_part = game_part;
    }

    /// Load the specified resource if it is not already loaded.
    /// Returns an error if the specified resource ID does not exist or could not be loaded.
    pub fn loadResource(self: *Self, resource_id: ResourceID) !void {
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
    pub fn drawPolygon(self: *Self, source: Video.PolygonSource, address: Video.PolygonAddress, point: Point, scale: PolygonScale.Raw) !void {
        try self.video.drawPolygon(source, address, point, scale);
    }

    /// Render a string from the current string table at the specified screen position in the specified color.
    /// Returns an error if the string could not be found.
    pub fn drawString(self: *Self, string_id: StringID.Raw, color_id: ColorID.Trusted, point: Point) !void {
        try self.video.drawString(string_id, color_id, point);
    }

    /// Select the active palette to render the video buffer in.
    pub fn selectPalette(self: *Self, palette_id: PaletteID.Trusted) !void {
        try self.video.selectPalette(palette_id);
    }

    /// Select the video buffer that subsequent drawPolygon and drawString operations will draw into.
    pub fn selectVideoBuffer(self: *Self, buffer_id: BufferID) void {
        self.video.selectBuffer(buffer_id);
    }

    /// Fill a specified video buffer with a single color.
    pub fn fillVideoBuffer(self: *Self, buffer_id: BufferID, color_id: ColorID.Trusted) void {
        self.video.fillBuffer(buffer_id, color_id);
    }

    /// Copy the contents of one video buffer into another at the specified vertical offset.
    pub fn copyVideoBuffer(self: *Self, source: BufferID, destination: BufferID, vertical_offset: Point.Coordinate) void {
        self.video.copyBuffer(source, destination, vertical_offset);
    }

    /// Render the contents of the specified buffer to the host screen after the specified delay.
    pub fn renderVideoBuffer(self: *Self, buffer_id: BufferID, delay: Video.Milliseconds) void {
        const buffer_to_draw = self.video.markBufferAsReady(buffer_id);
        self.host.bufferReady(self, buffer_to_draw, delay);
    }

    /// Called by the host to render the specified buffer into a 24-bit host surface.
    pub fn renderBufferToSurface(self: *const Self, buffer_id: BufferID.Specific, surface: *Video.HostSurface) !void {
        try self.video.renderBufferToSurface(buffer_id, surface);
    }

    // -- Audio subsystem interface --

    /// Start playing a music track from a specified resource.
    /// Returns an error if the resource does not exist or could not be loaded.
    pub fn playMusic(_: *Self, resource_id: ResourceID, offset: Audio.Offset, delay: Audio.Delay) !void {
        log.debug("Audio.playMusic: play #{X} at offset {} after delay {}", .{
            resource_id,
            offset,
            delay,
        });
    }

    /// Set on the current or subsequent music track.
    pub fn setMusicDelay(_: *Self, delay: Audio.Delay) void {
        log.debug("Audio.setMusicDelay: set delay to {}", .{delay});
    }

    /// Stop playing any current music track.
    pub fn stopMusic(_: *Self) void {
        log.debug("Audio.stopMusic: stop playing", .{});
    }

    /// Play a sound effect from the specified resource on the specified channel.
    /// Returns an error if the resource does not exist or could not be loaded.
    pub fn playSound(_: *Self, resource_id: ResourceID, channel: Channel.Trusted, volume: Audio.Volume, frequency: Audio.Frequency) !void {
        log.debug("Audio.playSound: play #{X} on channel {} at volume {}, frequency {}", .{
            resource_id,
            channel,
            volume,
            frequency,
        });
    }

    /// Stop any sound effect playing on the specified channel.
    pub fn stopChannel(_: *Self, channel: Channel.Trusted) void {
        log.debug("Audio.stopChannel: stop playing on channel {}", .{channel});
    }

    // - Private methods -

    /// Update the machine's registers to reflect the current state of the user's input.
    fn applyUserInput(self: *Self, input: UserInput) void {
        const register_values = input.registerValues();

        self.registers.setSigned(.left_right_input, register_values.left_right_input);
        self.registers.setSigned(.up_down_input, register_values.up_down_input);
        // TODO: explore why the reference implementation recorded the up/down state
        // into two different registers, by checking which game parts read from each register.
        self.registers.setSigned(.up_down_input_2, register_values.up_down_input);
        self.registers.setSigned(.action_input, register_values.action_input);
        self.registers.setBitPattern(.movement_inputs, register_values.movement_inputs);
        self.registers.setBitPattern(.all_inputs, register_values.all_inputs);

        // TODO: check if the `last_pressed_character` register is read during any other game part;
        // we may be able to unconditionally set it.
        if (self.current_game_part == .password_entry) {
            self.registers.setUnsigned(.last_pressed_character, register_values.last_pressed_character);
        }

        if (input.show_password_screen and self.current_game_part.allowsPasswordEntry()) {
            self.scheduleGamePart(.password_entry);
        }
    }

    /// Immediately unload all resources, load the resources for the specified game part,
    /// and prepare to execute its bytecode.
    /// Returns an error if one or more resources do not exist or could not be loaded.
    /// Not intended to be called during thread execution: instead call `scheduleGamePart`,
    /// which will let the current game tic finish executing all threads before beginning
    /// the new game part on the next run loop.
    fn startGamePart(self: *Self, game_part: GamePart) !void {
        const resource_locations = try self.memory.loadGamePart(game_part);
        self.program = Program.init(resource_locations.bytecode);

        self.video.setResourceLocations(resource_locations.palettes, resource_locations.polygons, resource_locations.animations);

        // Clear the state of all threads.
        for (self.threads) |*thread| {
            thread.reset();
        }

        // Reset the main thread to begin execution at the start of the current program.
        self.threads[ThreadID.main].start();

        self.current_game_part = game_part;
        self.scheduled_game_part = null;

        log.debug("Started game part {}", .{game_part});
    }

    // - Exported constants -

    /// Optional configuration options for a virtual machine instance.
    pub const Options = struct {
        /// Which game part to start up with.
        /// TODO: default this to .intro_cinematic once the copy protection bypass is working fully.
        initial_game_part: GamePart = .copy_protection,

        /// The seed to use for the game's random number generator.
        /// If null, a random seed will be chosen based on the system clock.
        seed: ?Register.Signed = null,
    };

    /// Optional configuration settings for the test machine instance created by `testInstance`.
    pub const TestInstanceConfig = struct {
        // Optional bytecode to load as the machine's program.
        bytecode: ?[]const u8 = null,
        // An optional host that the test instance should talk to.
        host: ?Host = null,
    };

    /// Returns a machine instance suitable for use in tests.
    /// The machine will load game data from a fake repository,
    /// and will be optionally be initialized with the specified bytecode program and host.
    ///
    /// Usage:
    /// ------
    /// const machine = Machine.testInstance(.{});
    /// defer machine.deinit();
    /// try testing.expectEqual(result, do_something_that_requires_a_machine(machine));
    pub fn testInstance(config: TestInstanceConfig) Self {
        const options = Options{ .initial_game_part = .intro_cinematic, .seed = 0 };
        const host = config.host orelse mock_host.test_host;

        var machine = Self.init(testing.allocator, MockRepository.test_reader, host, options) catch unreachable;
        if (config.bytecode) |bytecode| {
            machine.program = Program.init(bytecode);
        }
        return machine;
    }
};

// -- Tests --

const testing = @import("../utils/testing.zig");
const meta = @import("std").meta;

// - Initialization tests -

test "new creates virtual machine instance with expected initial state" {
    const options = Machine.Options{
        .initial_game_part = .gameplay1,
        .seed = 12345,
    };

    var machine = try Machine.init(testing.allocator, MockRepository.test_reader, mock_host.test_host, options);
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
        const expected_value: Register.Unsigned = switch (@intToEnum(RegisterID, id)) {
            .virtual_machine_startup_UNKNOWN => 0x81,
            .copy_protection_bypass_1 => 0b0001_0000,
            .copy_protection_bypass_2 => 0x0080,
            .copy_protection_bypass_3 => 0x0021,
            .copy_protection_bypass_4 => 0x0FA0,
            .random_seed => 12345,
            else => 0,
        };
        try testing.expectEqual(expected_value, register);
    }

    try testing.expectEqual(null, machine.scheduled_game_part);

    // Ensure each resource was loaded for the requested game part
    // and passed to the program and video subsystems
    const resource_ids = options.initial_game_part.resourceIDs();

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

// - Game-part loading tests -

test "startGamePart resets previous thread state, loads resources for new game part, and unloads previously-loaded resources, but leaves register state alone" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    // Pollute the current and scheduled thread states
    for (machine.threads) |*thread| {
        thread.execution_state = .{ .active = 0xDEAD };
        thread.pause_state = .paused;
        thread.scheduleJump(0xBEEF);
        thread.schedulePause();
    }

    // Pollute the register state
    for (machine.registers.unsignedSlice()) |*register| {
        register.* = 0xBEEF;
    }

    const next_game_part = GamePart.arena_cinematic;
    try testing.expect(machine.current_game_part != next_game_part);

    const current_resource_ids = machine.current_game_part.resourceIDs();
    const next_resource_ids = next_game_part.resourceIDs();

    try testing.expect((try machine.memory.resourceLocation(current_resource_ids.bytecode)) != null);
    try testing.expect((try machine.memory.resourceLocation(current_resource_ids.palettes)) != null);
    try testing.expect((try machine.memory.resourceLocation(current_resource_ids.polygons)) != null);

    try testing.expectEqual(null, try machine.memory.resourceLocation(next_resource_ids.bytecode));
    try testing.expectEqual(null, try machine.memory.resourceLocation(next_resource_ids.palettes));
    try testing.expectEqual(null, try machine.memory.resourceLocation(next_resource_ids.polygons));

    try machine.startGamePart(next_game_part);

    for (machine.threads) |thread, id| {
        if (id == ThreadID.main) {
            try testing.expectEqual(.{ .active = 0 }, thread.execution_state);
        } else {
            try testing.expectEqual(.inactive, thread.execution_state);
        }
        try testing.expectEqual(.running, thread.pause_state);

        try testing.expectEqual(null, thread.scheduled_execution_state);
        try testing.expectEqual(null, thread.scheduled_pause_state);
    }

    for (machine.registers.unsignedSlice()) |register| {
        try testing.expectEqual(0xBEEF, register);
    }

    try testing.expectEqual(next_game_part, machine.current_game_part);
    try testing.expectEqual(null, machine.scheduled_game_part);

    try testing.expectEqual(null, try machine.memory.resourceLocation(current_resource_ids.bytecode));
    try testing.expectEqual(null, try machine.memory.resourceLocation(current_resource_ids.palettes));
    try testing.expectEqual(null, try machine.memory.resourceLocation(current_resource_ids.polygons));

    try testing.expect((try machine.memory.resourceLocation(next_resource_ids.bytecode)) != null);
    try testing.expect((try machine.memory.resourceLocation(next_resource_ids.palettes)) != null);
    try testing.expect((try machine.memory.resourceLocation(next_resource_ids.polygons)) != null);
}

test "scheduleGamePart schedules a new game part without loading it" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    try testing.expectEqual(null, machine.scheduled_game_part);

    const current_game_part = machine.current_game_part;
    const next_game_part = GamePart.arena_cinematic;
    try testing.expect(current_game_part != next_game_part);

    const resource_ids = next_game_part.resourceIDs();

    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.bytecode));
    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.palettes));
    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.polygons));

    machine.scheduleGamePart(next_game_part);
    try testing.expectEqual(next_game_part, machine.scheduled_game_part);
    try testing.expectEqual(current_game_part, machine.current_game_part);

    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.bytecode));
    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.palettes));
    try testing.expectEqual(null, try machine.memory.resourceLocation(resource_ids.polygons));
}

// - loadResource tests -

test "loadResource loads audio resource into main memory" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    const audio_resource_id = MockRepository.Fixtures.sfx_resource_id;

    try testing.expectEqual(null, try machine.memory.resourceLocation(audio_resource_id));
    try machine.loadResource(audio_resource_id);
    try testing.expect((try machine.memory.resourceLocation(audio_resource_id)) != null);
}

test "loadResource copies bitmap resource directly into video buffer without persisting in main memory" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    const buffer = &machine.video.buffers[Video.bitmap_buffer_id];
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
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    const invalid_id = MockRepository.Fixtures.invalid_resource_id;
    try testing.expectError(error.InvalidResourceID, machine.loadResource(invalid_id));
}

// - applyUserInput tests -

test "applyUserInput sets expected register values" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    const full_input = UserInput{
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

    const empty_input = UserInput{};
    machine.applyUserInput(empty_input);

    try testing.expectEqual(0, machine.registers.signed(.action_input));
    try testing.expectEqual(0, machine.registers.signed(.left_right_input));
    try testing.expectEqual(0, machine.registers.signed(.up_down_input));
    try testing.expectEqual(0, machine.registers.signed(.up_down_input_2));
    try testing.expectEqual(0b0000, machine.registers.bitPattern(.movement_inputs));
    try testing.expectEqual(0b0000_0000, machine.registers.bitPattern(.all_inputs));
}

test "applyUserInput sets RegisterID.last_pressed_character when in password entry screen" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    try machine.startGamePart(.password_entry);

    const original_value = 1234;
    machine.registers.setUnsigned(.last_pressed_character, original_value);

    const input = UserInput{ .last_pressed_character = 'a' };
    machine.applyUserInput(input);

    try testing.expectEqual('A', machine.registers.unsigned(.last_pressed_character));
}

test "applyUserInput does not touch RegisterID.last_pressed_character during other game parts" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    try testing.expect(machine.current_game_part != .password_entry);

    const original_value = 1234;
    machine.registers.setUnsigned(.last_pressed_character, original_value);

    const input = UserInput{ .last_pressed_character = 'a' };
    machine.applyUserInput(input);

    try testing.expectEqual(original_value, machine.registers.unsigned(.last_pressed_character));
}

test "applyUserInput opens password screen if permitted for current game part" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    try testing.expectEqual(.intro_cinematic, machine.current_game_part);

    const input = UserInput{ .show_password_screen = true };
    machine.applyUserInput(input);

    try testing.expectEqual(.password_entry, machine.scheduled_game_part);
}

test "applyUserInput does not open password screen when in copy protection" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    try machine.startGamePart(.copy_protection);

    const input = UserInput{ .show_password_screen = true };
    machine.applyUserInput(input);

    try testing.expectEqual(null, machine.scheduled_game_part);
}

test "applyUserInput does not open password screen when already in password screen" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    try machine.startGamePart(.password_entry);

    const input = UserInput{ .show_password_screen = true };
    machine.applyUserInput(input);

    try testing.expectEqual(null, machine.scheduled_game_part);
}

// - runTic tests -

const Opcode = @import("../values/opcode.zig").Opcode;
const ThreadOperation = @import("../instructions/thread_operation.zig").ThreadOperation;

test "runTic starts next game part if scheduled" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    const next_game_part = .arena_cinematic;
    try testing.expect(machine.current_game_part != next_game_part);

    machine.scheduleGamePart(next_game_part);

    try machine.runTic(UserInput{});

    try testing.expectEqual(next_game_part, machine.current_game_part);
    try testing.expectEqual(null, machine.scheduled_game_part);
}

test "runTic applies user input only after loading scheduled game part" {
    var machine = Machine.testInstance(.{});
    defer machine.deinit();

    machine.scheduleGamePart(.password_entry);

    try testing.expect(machine.current_game_part != .password_entry);
    try testing.expectEqual(0, machine.registers.signed(.left_right_input));
    try testing.expectEqual(0, machine.registers.unsigned(.last_pressed_character));

    const input = UserInput{ .left = true, .last_pressed_character = 'A' };

    try machine.runTic(input);

    try testing.expectEqual(.password_entry, machine.current_game_part);
    try testing.expectEqual(-1, machine.registers.signed(.left_right_input));
    // This would have remained 0 if user input was processed *before* the game part was switched.
    try testing.expectEqual('A', machine.registers.unsigned(.last_pressed_character));
}

test "runTic updates each thread with its scheduled state before running each thread" {
    var bytecode = [_]u8{
        // Schedule threads 1-63 to unpause on the next tic
        @enumToInt(Opcode.ControlThreads), 1, 63, @enumToInt(ThreadOperation.@"resume"),
        // Deactivate the current thread (expected to be 0) immediately on this tic
        @enumToInt(Opcode.Kill),
    };

    var machine = Machine.testInstance(.{ .bytecode = &bytecode });
    defer machine.deinit();

    const main_thread = &machine.threads[0];

    // Schedule every thread except the main thread to pause when the next tic is run.
    for (machine.threads[1..64]) |*thread| {
        thread.schedulePause();

        try testing.expectEqual(.running, thread.pause_state);
        try testing.expectEqual(.inactive, thread.execution_state);

        try testing.expectEqual(.paused, thread.scheduled_pause_state);
        try testing.expectEqual(null, thread.scheduled_execution_state);
    }

    // Make sure the main thread is ready to execute the program.
    try testing.expectEqual(.{ .active = 0x0 }, main_thread.execution_state);
    try testing.expectEqual(.running, main_thread.pause_state);
    try testing.expectEqual(null, main_thread.scheduled_pause_state);
    try testing.expectEqual(null, main_thread.scheduled_execution_state);

    try machine.runTic(UserInput{});

    for (machine.threads[1..64]) |*thread| {
        // Every thread except main should have remained inactive.
        try testing.expectEqual(.inactive, thread.execution_state);
        // Every thread except main should now be paused by applying its scheduled state.
        try testing.expectEqual(.paused, thread.pause_state);

        // Every thread except main should now be scheduled to resume next tic
        // thanks to the ControlThreads instruction.
        try testing.expectEqual(.running, thread.scheduled_pause_state);
        try testing.expectEqual(null, thread.scheduled_execution_state);
    }

    // The main thread should now be be deactivated thanks to the Kill instruction.
    try testing.expectEqual(.inactive, main_thread.execution_state);
    try testing.expectEqual(.running, main_thread.pause_state);
    try testing.expectEqual(null, main_thread.scheduled_execution_state);
    try testing.expectEqual(null, main_thread.scheduled_pause_state);
}

// - renderVideoBuffer tests -

test "renderVideoBuffer notifies host of new frame with expected buffer ID and delay" {
    const expected_buffer_id = 3;
    const expected_delay = 24;

    var host = mock_host.mockHost(struct {
        pub fn bufferReady(_: *const Machine, buffer_id: BufferID.Specific, delay: Host.Milliseconds) void {
            testing.expectEqual(expected_buffer_id, buffer_id) catch unreachable;
            testing.expectEqual(expected_delay, delay) catch unreachable;
        }
    });

    var machine = Machine.testInstance(.{ .host = host.host() });
    defer machine.deinit();

    machine.renderVideoBuffer(.{ .specific = expected_buffer_id }, expected_delay);
    try testing.expectEqual(1, host.call_counts.bufferReady);
}
