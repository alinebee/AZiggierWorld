//! Tools to make type introspection less painful and wordy.

const std = @import("std");

/// Given an integer type, returns the number of bits in that integer.
pub const bitCount = std.meta.bitCount;

/// Casts an integer type to another, returning an error on overflow (instead of trapping like @intCast).
pub const intCast = std.math.cast;

/// Given an integer type, returns the type used for legal left/right-shift operations.
pub const ShiftType = std.math.Log2Int;

// -- VTable shenanigans --

/// Given a struct whose fields are comptime-known functions that have been type-erased,
/// returns a vtable struct type whose fields are pointers to those functions.
pub fn VTable(comptime Template: type) type {
    const fields = @typeInfo(Template).Struct.fields;

    var erased_fields: [fields.len]std.builtin.Type.StructField = undefined;

    inline for (fields) |field, idx| {
        const WrapperFnPtr = *const VTableWrapperFnType(field.field_type);
        erased_fields[idx] = .{
            .name = field.name,
            .field_type = WrapperFnPtr,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(WrapperFnPtr),
        };
    }

    return @Type(.{
        .Struct = .{
            .is_tuple = false,
            .layout = .Auto,
            .decls = &.{},
            .fields = &erased_fields,
        },
    });
}

/// Given a function type or an optional function type, returns a version of that function
/// with the parameter list replaced by a single tuple of all parameters, suitable for
/// the fields of a vtable.
fn VTableWrapperFnType(comptime PossibleFn: type) type {
    switch (@typeInfo(PossibleFn)) {
        .Optional => |optional_info| {
            return VTableWrapperFnType(optional_info.child);
        },
        .Fn => |function_info| {
            const Fn = PossibleFn;
            const Return = function_info.return_type.?;
            return fn (args: std.meta.ArgsTuple(Fn)) Return;
        },
        else => {
            @compileError("PossibleFn must be a function or optional function");
        },
    }
}

// Given a type-erased vtable struct type created by `VTable`,
// and a struct whose fields are type-aware functions, returns a vtable instance
// whose fields are populated with wrapper functions that call those type-aware functions.
// TODO: attach this method as a declaration on the type returned by TypeErasedVTable?
pub fn initVTable(comptime Table: type, comptime type_aware_functions: anytype) Table {
    var table: Table = undefined;
    const fields = @typeInfo(Table).Struct.fields;
    inline for (fields) |field| {
        const function = @field(type_aware_functions, field.name);
        const TypeErasedWrapper = @TypeOf(@field(table, field.name));
        const wrapper = typeErasedWrap(TypeErasedWrapper, function);

        @field(table, field.name) = wrapper;
    }
    return table;
}

/// Given a type-erased function pointer type and a type-aware function or optional function
/// whose signature matches that type-erased function pointer, returns a pointer to a
/// a type-erased wrapper function that is suitable to store in a vtable.
/// If `function` is `null`, the typed-erased wrapper will be a no-op that returns either `void`
/// or `null` depending on the return type of the function.
fn typeErasedWrap(comptime TypeErasedWrapper: type, comptime function: anytype) TypeErasedWrapper {
    const TypeAwareFn = @TypeOf(function);

    const TypeErasedFn = @typeInfo(TypeErasedWrapper).Pointer.child;

    const erased_fn_info = @typeInfo(TypeErasedFn).Fn;
    const ErasedParams = erased_fn_info.args[0].arg_type.?;
    const Return = erased_fn_info.return_type.?;

    switch (@typeInfo(TypeAwareFn)) {
        .Optional => |optional_info| {
            const Fn = optional_info.child;
            const UnerasedParams = std.meta.ArgsTuple(Fn);

            const Prototype = struct {
                fn wrapped(params: ErasedParams) Return {
                    if (function) |unwrapped_function| {
                        const unerased_params = typeAwareArgs(UnerasedParams, params);
                        return @call(.{ .modifier = .always_inline }, unwrapped_function, unerased_params);
                    } else {
                        switch (@typeInfo(Return)) {
                            .Optional => {
                                return null;
                            },
                            .Void => {
                                return;
                            },
                            else => {
                                @compileError("Optional function must return optional or void");
                            },
                        }
                    }
                }
            };

            return &Prototype.wrapped;
        },
        .Fn => {
            const UnerasedParams = std.meta.ArgsTuple(TypeAwareFn);

            const Prototype = struct {
                fn wrapped(params: ErasedParams) Return {
                    const unerased_params = typeAwareArgs(UnerasedParams, params);
                    return @call(.{ .modifier = .always_inline }, function, unerased_params);
                }
            };
            return &Prototype.wrapped;
        },
        else => {
            @compileError("`function` must be a function or optional function");
        },
    }
}

/// Casts a type-erased tuple of function arguments to a type-aware version.
fn typeAwareArgs(comptime TypeAwareTuple: type, type_erased_args: anytype) TypeAwareTuple {
    // In Zig 0.9.1 it was possible to just @bitCast the type-erased tuple
    // to the type-aware one; Zig 0.10.0 no longer allows that on the grounds
    // that the tuple's in-memory layout is not well-defined.
    // This implementation likely copies the fields back and forth,
    // which is far from what we want.
    const tuple_fields = @typeInfo(TypeAwareTuple).Struct.fields;

    var type_aware_args: TypeAwareTuple = undefined;
    inline for (tuple_fields) |field, idx| {
        // FIXME: this assumes that the first parameter (and only the first parameter)
        // is type-erased.
        if (idx == 0) {
            @field(type_aware_args, field.name) = @ptrCast(field.field_type, @alignCast(field.alignment, @field(type_erased_args, field.name)));
        } else {
            @field(type_aware_args, field.name) = @field(type_erased_args, field.name);
        }
    }
    return type_aware_args;
}

// -- Everything else --

/// Return `value` cast to the specified integer type,
/// clamped to fit within the minimum and maximum bounds of that type.
/// Intended as a saturating version of `@truncate`.
pub fn saturatingCast(comptime Int: type, value: anytype) Int {
    const min = comptime std.math.minInt(Int);
    const max = comptime std.math.maxInt(Int);
    const clamped_value = std.math.clamp(value, min, max);
    return @intCast(Int, clamped_value);
}

/// The version of intToEnum in the Zig 0.9.1 Standard Library doesn't correctly handle
/// non-exhaustive enums.
pub fn intToEnum(comptime EnumTag: type, tag_int: anytype) std.meta.IntToEnumError!EnumTag {
    const enum_info = @typeInfo(EnumTag).Enum;

    if (enum_info.is_exhaustive) {
        inline for (enum_info.fields) |f| {
            const this_tag_value = @field(EnumTag, f.name);
            if (tag_int == @enumToInt(this_tag_value)) {
                return this_tag_value;
            }
        }

        return error.InvalidEnumTag;
    } else {
        const max = std.math.maxInt(enum_info.tag_type);
        const min = std.math.minInt(enum_info.tag_type);

        if (tag_int >= min and tag_int <= max) {
            return @intToEnum(EnumTag, tag_int);
        } else {
            return error.InvalidEnumTag;
        }
    }
}

/// If given a type directly, returns that type.
/// If given a value, returns the type of that value.
pub fn TypeOf(comptime type_or_value: anytype) type {
    const Type = @TypeOf(type_or_value);
    return if (Type == type) type_or_value else Type;
}

/// If given a pointer type, returns the type that the pointer points to;
/// if given any other type, returns the base type.
/// Intended to simplify the introspection of `anytype` parameters that may be passed by reference or by value.
pub fn BaseType(comptime pointer_type_or_value_type: type) type {
    const type_info = @typeInfo(pointer_type_or_value_type);
    return switch (type_info) {
        .Pointer => |info| info.child,
        else => pointer_type_or_value_type,
    };
}

/// Given a function type, function value or function pointer, returns the return type of the function it describes.
pub fn ReturnType(comptime function: anytype) type {
    return switch (@typeInfo(TypeOf(function))) {
        .Fn => |info| info.return_type.?,
        .BoundFn => |info| info.return_type.?,
        .Pointer => |info| ReturnType(info.child),
        else => @compileError("Parameter was not a function or pointer to function"),
    };
}

/// Given a function that returns a regular type, an optional (`?payload`)
/// or an error union (`error_set!payload`), returns the type of the payload.
pub fn PayloadType(comptime function: anytype) type {
    const return_type = ReturnType(function);
    return switch (@typeInfo(return_type)) {
        .ErrorUnion => |info| info.payload,
        .Optional => |info| info.child,
        else => return_type,
    };
}

/// Given a function that returns an error union (`error_set!payload`),
/// returns the type of the error set.
/// Returns a compile error if the function does not return an error union.
pub fn ErrorType(comptime function: anytype) type {
    const return_type = ReturnType(function);
    return switch (@typeInfo(return_type)) {
        .ErrorUnion => |info| info.error_set,
        else => @compileError("Parameter did not return an ErrorUnion"),
    };
}

// -- Tests --

const testing = @import("testing.zig");

test "ReturnType gets return type of free function" {
    const Namespace = struct {
        fn example() void {}
    };

    try testing.expectEqual(void, ReturnType(Namespace.example));
}

test "ReturnType gets return type of bound function" {
    const Struct = struct {
        const Self = @This();

        fn boundExample(_: Self) void {}
    };

    const foo = Struct{};
    try testing.expectEqual(void, ReturnType(foo.boundExample));
}

test "ReturnType triggers compile error when passed non-function type" {
    // Uncomment me to trigger a compile error!
    // _ = ReturnType(u32);
}

test "PayloadType gets return type of function that returns a type directly" {
    const Namespace = struct {
        fn example() u32 {
            return 0;
        }
    };

    try testing.expectEqual(u32, PayloadType(Namespace.example));
}

test "PayloadType gets return type of function that returns an optional" {
    const Namespace = struct {
        fn example() ?u32 {
            return null;
        }
    };

    try testing.expectEqual(u32, PayloadType(Namespace.example));
}

test "PayloadType gets return type of function that returns an error union" {
    const Namespace = struct {
        fn example() anyerror!u32 {
            return 0;
        }
    };

    try testing.expectEqual(u32, PayloadType(Namespace.example));
}

test "ErrorType gets return type of function that returns an error union" {
    const CustomError = error{FlagrantViolation};
    const Namespace = struct {
        fn example() CustomError!u32 {
            return 255;
        }
    };

    try testing.expectEqual(CustomError, ErrorType(Namespace.example));
}

test "ErrorType returns compile error when given function that does not return an error union" {
    // Uncomment to trigger a compile-time error!
    // const Namespace = struct {
    //     fn example() void {}
    // };

    //_ = ErrorType(Namespace.example);
}

test "BaseType returns struct type when given a pointer to a struct" {
    const MyStruct = struct { foo: usize };

    const pointer_to_struct: *MyStruct = undefined;

    try testing.expectEqual(MyStruct, BaseType(@TypeOf(pointer_to_struct)));
}

test "BaseType returns struct type when given a struct type" {
    const MyStruct = struct { foo: usize };

    const value_of_struct: MyStruct = undefined;

    try testing.expectEqual(MyStruct, BaseType(@TypeOf(value_of_struct)));
}

// -- intToEnum tests

const ExhaustiveEnumWithInferredTag = enum {
    first,
    second,
};

const ExhaustiveEnumWithExplicitTag = enum(i8) {
    first = 0,
    second = 1,
};

const NonExhaustiveEnum = enum(i8) {
    first = 0,
    second = 1,
    _,
};

const standardLibraryIntToEnum = std.meta.intToEnum;

test "intToEnum with non-exhaustive enum" {
    _ = try intToEnum(NonExhaustiveEnum, 0);
    _ = try intToEnum(NonExhaustiveEnum, 1);
    _ = try intToEnum(NonExhaustiveEnum, 127);
    _ = try intToEnum(NonExhaustiveEnum, -128);
    try testing.expectError(error.InvalidEnumTag, intToEnum(NonExhaustiveEnum, 256));
    try testing.expectError(error.InvalidEnumTag, intToEnum(NonExhaustiveEnum, -256));
}

test "intToEnum with exhaustive enum" {
    _ = try intToEnum(ExhaustiveEnumWithExplicitTag, 0);
    _ = try intToEnum(ExhaustiveEnumWithExplicitTag, 1);
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithExplicitTag, 127));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithExplicitTag, -128));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithExplicitTag, 256));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithExplicitTag, -256));
}

test "intToEnum with exhaustive enum with inferred tag" {
    _ = try intToEnum(ExhaustiveEnumWithInferredTag, 0);
    _ = try intToEnum(ExhaustiveEnumWithInferredTag, 1);
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithInferredTag, 127));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithInferredTag, -128));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithInferredTag, 256));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithInferredTag, -256));
}

test "Standard Library intToEnum has buggy handling of non-exhaustive enums" {
    _ = try standardLibraryIntToEnum(NonExhaustiveEnum, 0);
    _ = try standardLibraryIntToEnum(NonExhaustiveEnum, 1);
    try testing.expectError(error.InvalidEnumTag, standardLibraryIntToEnum(NonExhaustiveEnum, 256));
    try testing.expectError(error.InvalidEnumTag, standardLibraryIntToEnum(NonExhaustiveEnum, -256));

    // These two expectations will start failing once the bug is fixed upstream,
    // at which point we can get rid of our overridden implementation.
    try testing.expectError(error.InvalidEnumTag, standardLibraryIntToEnum(NonExhaustiveEnum, 127));
    try testing.expectError(error.InvalidEnumTag, standardLibraryIntToEnum(NonExhaustiveEnum, -128));
}

// -- saturatingCast tests

test "saturatingCast clamps unsigned integer to unsigned integer" {
    const value: i32 = 12345678;
    try testing.expectEqual(255, saturatingCast(u8, value));
}

test "saturatingCast clamps unsigned integer to signed integer" {
    const value: u32 = 12345678;
    try testing.expectEqual(127, saturatingCast(i8, value));
}

test "saturatingCast clamps signed integer to unsigned integer" {
    const negative_value: i32 = -12345678;
    const positive_value: i32 = 12345678;
    try testing.expectEqual(0, saturatingCast(u8, negative_value));
    try testing.expectEqual(255, saturatingCast(u8, positive_value));
}

test "saturatingCast clamps signed integer to signed integer" {
    const negative_value: i32 = -12345678;
    const positive_value: i32 = 12345678;
    try testing.expectEqual(-128, saturatingCast(i8, negative_value));
    try testing.expectEqual(127, saturatingCast(i8, positive_value));
}

test "saturatingCast does not saturate in-range unsigned values" {
    const value: u32 = 254;
    try testing.expectEqual(254, saturatingCast(u8, value));
}

test "saturatingCast does not saturate in-range signed values" {
    const negative_value: i32 = -127;
    const positive_value: i32 = 126;
    try testing.expectEqual(-127, saturatingCast(i8, negative_value));
    try testing.expectEqual(126, saturatingCast(i8, positive_value));
}
