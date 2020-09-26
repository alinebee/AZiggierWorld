/// The scale at which to render a polygon.
/// This is a raw value that will be divided by 64 to determine the actual scale:
/// e.g. 64 is 1x, 32 is 0.5x, 96 is 1.5x, 256 is 4x etc.
pub const Raw = u16;

/// The default scale for polygon draw operations.
/// This renders polygons at their native size.
pub const default: Raw = 64;
