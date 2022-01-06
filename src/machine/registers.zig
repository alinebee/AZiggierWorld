const Register = @import("../values/register.zig");
const RegisterID = @import("../values/register_id.zig");

const static_limits = @import("../static_limits.zig");

const register_count = static_limits.register_count;

/// A bank of 256 16-bit registers, that can be read and written as either signed or unsigned values.
pub const Instance = struct {
    const UnsignedValues = [register_count]Register.Unsigned;
    const SignedValues = [register_count]Register.Signed;
    const BitPatternValues = [register_count]Register.BitPattern;

    values: UnsignedValues = .{0} ** register_count,

    const Self = @This();

    /// Get the value of the specified register as an unsigned value.
    pub fn unsigned(self: Self, id: RegisterID.Enum) Register.Unsigned {
        return @bitCast(Register.Unsigned, self.values[@enumToInt(id)]);
    }

    /// Set the value of the specified register to the specified unsigned value.
    pub fn setUnsigned(self: *Self, id: RegisterID.Enum, value: Register.Unsigned) void {
        self.values[@enumToInt(id)] = @bitCast(Register.Unsigned, value);
    }

    /// Get the value of the specified register as a signed value.
    pub fn signed(self: Self, id: RegisterID.Enum) Register.Signed {
        return @bitCast(Register.Signed, self.values[@enumToInt(id)]);
    }

    /// Set the value of the specified register to the specified signed value.
    pub fn setSigned(self: *Self, id: RegisterID.Enum, value: Register.Signed) void {
        self.values[@enumToInt(id)] = @bitCast(Register.Unsigned, value);
    }

    /// Get the value of the specified register as a signed value.
    pub fn bitPattern(self: Self, id: RegisterID.Enum) Register.BitPattern {
        return @bitCast(Register.BitPattern, self.values[@enumToInt(id)]);
    }

    /// Set the value of the specified register to the specified value.
    pub fn setBitPattern(self: *Self, id: RegisterID.Enum, value: Register.BitPattern) void {
        self.values[@enumToInt(id)] = @bitCast(Register.Unsigned, value);
    }

    /// A mutable view of the contents of all registers as unsigned values.
    pub fn unsignedSlice(self: *Self) *UnsignedValues {
        return @ptrCast(*UnsignedValues, &self.values);
    }

    /// A mutable view of the contents of all registers as signed values.
    pub fn signedSlice(self: *Self) *SignedValues {
        return @ptrCast(*SignedValues, &self.values);
    }

    /// A mutable view of the contents of all registers as raw bit patterns.
    pub fn bitPatternSlice(self: *Self) *BitPatternValues {
        return @ptrCast(*BitPatternValues, &self.values);
    }
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "Ensure everything compiles" {
    testing.refAllDecls(Instance);
}