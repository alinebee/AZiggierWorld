const anotherworld = @import("../anotherworld.zig");
const static_limits = anotherworld.static_limits;
const vm = anotherworld.vm;

const register_count = static_limits.register_count;

/// A bank of 256 16-bit registers, that can be read and written as either signed or unsigned values.
pub const Registers = struct {
    const UnsignedValues = [register_count]vm.Register.Unsigned;
    const SignedValues = [register_count]vm.Register.Signed;
    const BitPatternValues = [register_count]vm.Register.BitPattern;

    values: UnsignedValues = .{0} ** register_count,

    const Self = @This();

    /// Get the value of the specified register as an unsigned value.
    pub fn unsigned(self: Self, id: vm.RegisterID) vm.Register.Unsigned {
        return @bitCast(vm.Register.Unsigned, self.values[id.index()]);
    }

    /// Set the value of the specified register to the specified unsigned value.
    pub fn setUnsigned(self: *Self, id: vm.RegisterID, value: vm.Register.Unsigned) void {
        self.values[id.index()] = @bitCast(vm.Register.Unsigned, value);
    }

    /// Get the value of the specified register as a signed value.
    pub fn signed(self: Self, id: vm.RegisterID) vm.Register.Signed {
        return @bitCast(vm.Register.Signed, self.values[id.index()]);
    }

    /// Set the value of the specified register to the specified signed value.
    pub fn setSigned(self: *Self, id: vm.RegisterID, value: vm.Register.Signed) void {
        self.values[id.index()] = @bitCast(vm.Register.Unsigned, value);
    }

    /// Get the value of the specified register as a signed value.
    pub fn bitPattern(self: Self, id: vm.RegisterID) vm.Register.BitPattern {
        return @bitCast(vm.Register.BitPattern, self.values[id.index()]);
    }

    /// Set the value of the specified register to the specified value.
    pub fn setBitPattern(self: *Self, id: vm.RegisterID, value: vm.Register.BitPattern) void {
        self.values[id.index()] = @bitCast(vm.Register.Unsigned, value);
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

const testing = @import("utils").testing;

test "Ensure everything compiles" {
    testing.refAllDecls(Registers);
}
