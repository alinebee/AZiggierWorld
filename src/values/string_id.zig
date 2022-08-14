const _Raw = u16;

/// The identifier of a translated string to draw.
/// This is not guaranteed to be valid, and must be looked up in a language-specific string table.
pub const StringID = enum(_Raw) {
    _,

    /// Convert a raw integer parsed from bytecode into a valid StringID.
    pub fn cast(raw_id: Raw) StringID {
        return @intToEnum(StringID, raw_id);
    }

    /// Convert a string ID into an array index.
    pub fn index(id: StringID) usize {
        return @enumToInt(id);
    }

    /// A raw string identifier value as represented in Another World's bytecode.
    pub const Raw = _Raw;

    pub const Error = error{
        /// Bytecode specified a string ID that was not found in the current language's string table.
        InvalidStringID,
    };
};
