const anotherworld = @import("../lib/anotherworld.zig");

const Register = @import("../values/register.zig");

/// The current state of user input. Expected to be provided by the host on each tic.
pub const UserInput = struct {
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

    /// Whether the button to show the password entry screen was released this frame after being pressed.
    show_password_screen: bool = false,

    /// The ASCII character of the most recent key that was released this frame after being pressed.
    /// Used for text entry on the password entry screen.
    /// Leave as `null` if no key was released this frame, or if the most recently-released key
    /// has no ASCII equivalent.
    last_pressed_character: ?u8 = null,

    const Self = @This();

    // -- Machine register input values --

    /// Translates user input into values to insert into the appropriate registers,
    /// for the game's bytecode to read the state of the input.
    pub fn registerValues(self: Self) RegisterValues {
        // All values will initially be 0.
        var values = RegisterValues{};

        if (self.right) {
            values.left_right_input = 1;
            values.movement_inputs |= 0b0001;
        }

        if (self.left) {
            // Left movement takes precedence over right
            values.left_right_input = -1;
            values.movement_inputs |= 0b0010;
        }

        if (self.down) {
            values.up_down_input = 1;
            values.movement_inputs |= 0b0100;
        }

        if (self.up) {
            // Up movement takes precedence over down
            values.up_down_input = -1;
            values.movement_inputs |= 0b1000;
        }

        values.all_inputs |= values.movement_inputs;

        if (self.action) {
            values.action_input = 1;
            values.all_inputs |= 0b1000_0000;
        }

        if (self.last_pressed_character) |char| {
            values.last_pressed_character = normalizedCharacterRegisterValue(char);
        }

        return values;
    }
};

/// The Another World register values corresponding to an input state.
const RegisterValues = struct {
    /// The value to insert into `RegisterID.up_down_input`.
    /// Will be -1 if left is active, 1 if right is active, 0 if neither is active.
    up_down_input: Register.Signed = 0,

    /// The value to insert into `RegisterID.left_right_input`.
    /// Will be -1 if left is active, 1 if right is active, 0 if neither is active.
    left_right_input: Register.Signed = 0,

    /// The value to insert into `RegisterID.action_input`.
    /// Will be 1 if action is active, 0 otherwise.
    action_input: Register.Signed = 0,

    /// The value to insert into `RegisterID.movement_inputs`.
    /// Contains bitflags of the currently active movement directions:
    /// Bits 0, 1, 2, 3 correspond to right, left, down, up.
    movement_inputs: Register.BitPattern = 0b0000,

    /// The value to insert into `RegisterID.all_inputs`.
    /// Contains bitflags of the currently active movement directions plus action:
    /// Bits 0, 1, 2, 3 correspond to right, left, down, up, and bit 7 is the action flag.
    all_inputs: Register.BitPattern = 0b0000_0000,

    /// The value to insert into `RegisterID.last_pressed_character`.
    /// Contains the uppercased ASCII value of the most recently-pressed key,
    /// or `0` if the key is unknown or does not correspond to a supported character.
    last_pressed_character: Register.Unsigned = 0,
};

/// Given an ASCII character representing the most recently pressed key,
/// normalizes it into a value supported by the Another World bytecode.
/// Returns `0` if the character is unsupported.
fn normalizedCharacterRegisterValue(char: u8) Register.Unsigned {
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
        // The SDL reference implementation commented out code that permitted 0xD
        // (carriage return, SDL's SDLK_RETURN keycode).
        // We could reenable it if the Another World bytecode actually handles it.
        '\r' => 0,
        // All other keys should not be handled.
        else => 0,
    };
}

// -- Testing --

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(UserInput);
}

// - registerValues tests -

test "registerValues returns expected values on no input" {
    const input = UserInput{};
    const expected = RegisterValues{};
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected values on action input" {
    const input = UserInput{ .action = true };
    const expected = RegisterValues{
        .action_input = 1,
        .all_inputs = 0b1000_0000,
    };
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected values on key character input" {
    const input = UserInput{ .last_pressed_character = 'a' };
    const expected = RegisterValues{
        .last_pressed_character = 'A',
    };
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected value on right input" {
    const input = UserInput{ .right = true };
    const expected = RegisterValues{
        .left_right_input = 1,
        .movement_inputs = 0b0001,
        .all_inputs = 0b0000_0001,
    };
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected value on left input" {
    const input = UserInput{ .left = true };
    const expected = RegisterValues{
        .left_right_input = -1,
        .movement_inputs = 0b0010,
        .all_inputs = 0b0000_0010,
    };
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected value on up input" {
    const input = UserInput{ .down = true };
    const expected = RegisterValues{
        .up_down_input = 1,
        .movement_inputs = 0b0100,
        .all_inputs = 0b0000_0100,
    };
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected value on down input" {
    const input = UserInput{ .up = true };
    const expected = RegisterValues{
        .up_down_input = -1,
        .movement_inputs = 0b1000,
        .all_inputs = 0b0000_1000,
    };
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected value on left-and-right combined input" {
    const input = UserInput{ .left = true, .right = true };
    const expected = RegisterValues{
        // Left input should take precedence over right
        .left_right_input = -1,
        .movement_inputs = 0b0011,
        .all_inputs = 0b0000_0011,
    };
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected value on up-and-down combined input" {
    const input = UserInput{ .up = true, .down = true };
    const expected = RegisterValues{
        // Up input should take precedence over down
        .up_down_input = -1,
        .movement_inputs = 0b1100,
        .all_inputs = 0b0000_1100,
    };
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected value on up-and-left combined input" {
    const input = UserInput{ .up = true, .left = true };
    const expected = RegisterValues{
        .left_right_input = -1,
        .up_down_input = -1,
        .movement_inputs = 0b1010,
        .all_inputs = 0b0000_1010,
    };
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected value on down-and-right combined input" {
    const input = UserInput{ .down = true, .right = true };
    const expected = RegisterValues{
        .left_right_input = 1,
        .up_down_input = 1,
        .movement_inputs = 0b0101,
        .all_inputs = 0b0000_0101,
    };
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected value on all directions combined" {
    const input = UserInput{ .up = true, .down = true, .left = true, .right = true };
    const expected = RegisterValues{
        // Left should take precedence over right
        .left_right_input = -1,
        // Up should take precedence over right
        .up_down_input = -1,
        .movement_inputs = 0b1111,
        .all_inputs = 0b0000_1111,
    };
    try testing.expectEqual(expected, input.registerValues());
}

test "registerValues returns expected value on all inputs combined" {
    const input = UserInput{
        .up = true,
        .down = true,
        .left = true,
        .right = true,
        .action = true,
        .last_pressed_character = 'a',
    };
    const expected = RegisterValues{
        // Left should take precedence over right
        .left_right_input = -1,
        // Up should take precedence over right
        .up_down_input = -1,
        .action_input = 1,
        .movement_inputs = 0b1111,
        .all_inputs = 0b1000_1111,
        .last_pressed_character = 'A',
    };
    try testing.expectEqual(expected, input.registerValues());
}

// - normalizedCharacterRegisterValue tests -

test "normalizedCharacterRegisterValue returns expected values for explicitly handled characters" {
    const uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const lowercase = "abcdefghijklmnopqrstuvwxyz";
    const backspace = '\x08';
    const carriage_return = '\r';

    for (uppercase) |char| {
        try testing.expectEqual(char, normalizedCharacterRegisterValue(char));
    }

    // lowercase characters should be converted to uppercase
    for (lowercase) |char, index| {
        try testing.expectEqual(uppercase[index], normalizedCharacterRegisterValue(char));
    }

    try testing.expectEqual(8, normalizedCharacterRegisterValue(backspace));
    try testing.expectEqual(0, normalizedCharacterRegisterValue(carriage_return));
}

test "normalizedCharacterRegisterValue returns null for unsupported characters" {
    // These are not intended to be exhaustive 😁
    const numbers = "0123456789";
    const punctuation = ",./\\;:'\"<>{}()[]!@#$%^&*";

    for (numbers) |char| {
        try testing.expectEqual(0, normalizedCharacterRegisterValue(char));
    }

    for (punctuation) |char| {
        try testing.expectEqual(0, normalizedCharacterRegisterValue(char));
    }
}
