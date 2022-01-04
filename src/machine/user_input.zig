const Machine = @import("machine.zig");
const Register = @import("../values/register.zig");

/// The current state of user input. Expected to be provided by the host on each tic.
pub const Instance = struct {
    /// Whether the left movement input is currently activated.
    left: bool = false,

    /// Whether the right movement input is currently activated.
    right: bool = false,

    /// Whether the up movement input is currently activated.
    up: bool = false,

    /// Whether the down movement input is currently activated.
    down: bool = false,

    /// Whether the action button is currently activated.
    action: bool = false,

    /// Whether the button to show the password entry screen was just released after being pressed.
    show_password_screen: bool = false,

    /// The ASCII character of the most recently pressed key. Used for text entry on the password entry screen.
    /// Leave as null if no key has been pressed, or the most recently-pressed key has no ASCII equivalent.
    last_character_typed: ?u8 = null,

    const Self = @This();

    // -- Machine register input values --

    /// The value to insert into RegisterID.left_right_input.
    pub fn leftRightInputRegisterValue(self: Self) Register.Signed {
        // Reference implementation: left takes precedence over right
        if (self.left) return -1;
        if (self.right) return 1;
        return 0;
    }

    /// The value to insert into RegisterID.up_down_input.
    pub fn upDownInputRegisterValue(self: Self) Register.Signed {
        // Reference implementation: up takes precedence over down
        if (self.up) return -1;
        if (self.down) return 1;
        return 0;
    }

    /// The value to insert into RegisterID.action_input.
    pub fn actionInputRegisterValue(self: Self) Register.Signed {
        return if (self.action) 1 else 0;
    }

    /// The value to insert into RegisterID.movement_inputs.
    pub fn movementInputsRegisterValue(self: Self) Register.Mask {
        // zig fmt: off
        var mask: u4          = 0b0000;
        if (self.right) mask |= 0b0001;
        if (self.left)  mask |= 0b0010;
        if (self.down)  mask |= 0b0100;
        if (self.up)    mask |= 0b1000;
        // zig fmt: on

        return mask;
    }

    /// The value to insert into RegisterID.all_inputs.
    pub fn allInputsRegisterValue(self: Self) Register.Mask {
        var mask = self.movementInputsRegisterValue();
        if (self.action) mask |= 0b1000_0000; // 0x80
        return mask;
    }

    /// The value to insert into RegisterID.last_character_typed.
    /// Will be `nil` if the last character is unknown or not a supported character.
    /// Should only be used during the password entry sequence.
    pub fn lastCharacterTypedRegisterValue(self: Self) ?Register.Unsigned {
        if (self.last_character_typed) |char| {
            // TODO: It's not that we couldn't just dump *any* ASCII code into the register after lowercasing it,
            // and let the bytecode just ignore unsupported values, but for now this matches the behaviour
            // of the reference implementation (which was working with SDL keycodes rather than ASCII values):
            // https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/vm.cpp#L590-L596
            return switch (char) {
                'A'...'Z' => |uppercase_char| uppercase_char,
                'a'...'z' => |lowercase_char| {
                    // In ASCII, a-z are the same bit pattern as A-Z just with bit 6 set;
                    // the reference implementation normalizes them to uppercase by unsetting that bit.
                    const lowercase_bitmask: u8 = 0b0010_0000;
                    const uppercase_char = lowercase_char & ~lowercase_bitmask;
                    return uppercase_char;
                },
                // The SDL reference implementation permitted 8 (backspace, SDL's SDLK_BACKSPACE keycode).
                '\x08' => 8,
                // The SDL reference implementation permitted 0 (NUL, SDL's SDLK_UNKNOWN keycode),
                // though it's unclear when that would ever be sent by the host.
                '\x00' => 0,
                // The SDL reference implementation commented out code that permitted 0xD
                // (carriage return, SDL's SDLK_RETURN keycode).
                // We could reenable it if the Another World bytecode actually responds to it.
                '\r' => null,
                // All other keys should not be sent.
                else => null,
            };
        } else {
            return null;
        }
    }
};

// -- Fixture data --

const Fixtures = struct {
    const no_inputs = Instance{};
    const action_pressed = Instance{ .action = true };
    const left = Instance{ .left = true };
    const right = Instance{ .right = true };
    const up = Instance{ .up = true };
    const down = Instance{ .down = true };
    const left_and_right = Instance{ .right = true, .left = true };
    const up_and_down = Instance{ .up = true, .down = true };
    const left_and_up = Instance{ .left = true, .up = true };
    const right_and_down = Instance{ .right = true, .down = true };
    const all_directions = Instance{ .left = true, .right = true, .up = true, .down = true };
    const all_inputs = Instance{ .action = true, .left = true, .right = true, .up = true, .down = true };
};

// -- Testing --

const testing = @import("../utils/testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(Instance);
}

test "leftRightInputRegisterValue returns expected movement inputs" {
    try testing.expectEqual(0, Fixtures.no_inputs.leftRightInputRegisterValue());
    try testing.expectEqual(-1, Fixtures.left.leftRightInputRegisterValue());
    try testing.expectEqual(1, Fixtures.right.leftRightInputRegisterValue());
    // Should prioritise left input
    try testing.expectEqual(-1, Fixtures.left_and_right.leftRightInputRegisterValue());
}

test "upDownInputRegisterValue returns expected movement inputs" {
    try testing.expectEqual(0, Fixtures.no_inputs.upDownInputRegisterValue());
    try testing.expectEqual(-1, Fixtures.up.upDownInputRegisterValue());
    try testing.expectEqual(1, Fixtures.down.upDownInputRegisterValue());
    // Should prioritise up input
    try testing.expectEqual(-1, Fixtures.up_and_down.upDownInputRegisterValue());
}

test "actionInputRegisterValue returns expected movement inputs" {
    try testing.expectEqual(0, Fixtures.no_inputs.actionInputRegisterValue());
    try testing.expectEqual(1, Fixtures.action_pressed.actionInputRegisterValue());
}

test "movementInputsRegisterValue returns expected movement inputs" {
    try testing.expectEqual(0b0000, Fixtures.no_inputs.movementInputsRegisterValue());
    try testing.expectEqual(0b0001, Fixtures.right.movementInputsRegisterValue());
    try testing.expectEqual(0b0010, Fixtures.left.movementInputsRegisterValue());
    try testing.expectEqual(0b0100, Fixtures.down.movementInputsRegisterValue());
    try testing.expectEqual(0b1000, Fixtures.up.movementInputsRegisterValue());
    try testing.expectEqual(0b1010, Fixtures.left_and_up.movementInputsRegisterValue());
    try testing.expectEqual(0b0101, Fixtures.right_and_down.movementInputsRegisterValue());
    try testing.expectEqual(0b1111, Fixtures.all_directions.movementInputsRegisterValue());
    try testing.expectEqual(0b1111, Fixtures.all_inputs.movementInputsRegisterValue());
}

test "allInputsRegisterValue combines expected movement inputs with action input" {
    try testing.expectEqual(0b0000_1111, Fixtures.all_directions.allInputsRegisterValue());
    try testing.expectEqual(0b1000_1111, Fixtures.all_inputs.allInputsRegisterValue());
}

test "lastCharacterTypedRegisterValue returns expected values" {
    const all_uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    for (all_uppercase) |char| {
        const input = Instance{ .last_character_typed = char };

        try testing.expectEqual(char, input.lastCharacterTypedRegisterValue());
    }
}

test "lastCharacterTypedRegisterValue returns expected values for supported characters" {
    const uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const lowercase = "abcdefghijklmnopqrstuvwxyz";
    const backspace = '\x08';
    const NUL = '\x00';
    const carriage_return = '\r';

    for (uppercase) |char| {
        const input = Instance{ .last_character_typed = char };
        try testing.expectEqual(char, input.lastCharacterTypedRegisterValue());
    }

    // lowercase characters should be converted to uppercase
    for (lowercase) |char, index| {
        const input = Instance{ .last_character_typed = char };
        try testing.expectEqual(uppercase[index], input.lastCharacterTypedRegisterValue());
    }

    {
        const input = Instance{ .last_character_typed = backspace };
        try testing.expectEqual(8, input.lastCharacterTypedRegisterValue());
    }

    {
        const input = Instance{ .last_character_typed = NUL };
        try testing.expectEqual(0, input.lastCharacterTypedRegisterValue());
    }

    {
        const input = Instance{ .last_character_typed = carriage_return };
        try testing.expectEqual(null, input.lastCharacterTypedRegisterValue());
    }
}

test "lastCharacterTypedRegisterValue returns null when last character is not a supported character" {
    // These are not intended to be exhaustive 😁
    const numbers = "0123456789";
    const punctuation = ",./\\;:'\"<>{}()[]!@#$%^&*";

    for (numbers) |char| {
        const input = Instance{ .last_character_typed = char };
        try testing.expectEqual(null, input.lastCharacterTypedRegisterValue());
    }

    for (punctuation) |char| {
        const input = Instance{ .last_character_typed = char };
        try testing.expectEqual(null, input.lastCharacterTypedRegisterValue());
    }
}

test "lastCharacterTypedRegisterValue returns null when last character is unknown" {
    const input = Instance{ .last_character_typed = null };
    try testing.expectEqual(null, input.lastCharacterTypedRegisterValue());
}
