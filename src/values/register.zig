//! Register values can interpreted as signed or unsigned 16-bit integers.
const introspection = @import("../utils/introspection.zig");

/// A 16-bit register value interpreted as a signed integer.
/// Intended for signed arithmetic.
pub const Signed = i16;
/// A 16-bit register value interpreted as an unsigned integer.
/// Intended for unsigned arithmetic.
pub const Unsigned = u16;
/// A 16-bit register value interpreted as a pattern of 16 raw bits.
/// Intended for bitmasking and shifting.
pub const BitPattern = Unsigned;

/// The integer type used for bit-shift operations.
/// Example:
/// --------
/// const shift: Shift = 6;
/// const shifted_value = @as(BitPattern, 0b0000_0000_0000_1000) << 6
pub const Shift = introspection.ShiftType(BitPattern);
