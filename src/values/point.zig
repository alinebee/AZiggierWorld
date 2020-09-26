pub const Coordinate = i16;

/// Defines an X,Y point in screen space.
pub const Instance = struct {
    /// The X position in virtual 320x200 pixels, starting from the left edge of the screen.
    x: Coordinate,

    /// The Y position in virtual 320x200 pixels, starting from the top edge of the screen.
    y: Coordinate,
};

pub const zero = Instance { .x = 0, .y = 0 };
