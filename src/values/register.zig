//! Register values can interpreted as signed or unsigned 16-bit integers.
const introspection = @import("../utils/introspection.zig");

pub const Signed = i16;
pub const Unsigned = u16;
pub const Mask = Unsigned;
pub const Shift = introspection.ShiftType(Unsigned);
