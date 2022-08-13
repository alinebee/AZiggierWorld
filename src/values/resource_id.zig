/// An Another World game resource as represented in Another World's bytecode and GamePart definitions.
const _Raw = u16;

pub const ResourceID = enum(_Raw) {
    // Allow Resource IDs with any 16-bit unsigned integer.
    // (Any ResourceID is valid at compile time; their validity depends on the runtime resource repository.)
    _,

    // Convert a raw integer into a ResourceID.
    pub fn cast(raw: Raw) ResourceID {
        return @intToEnum(ResourceID, raw);
    }

    /// Returns the ResourceID converted to an array index.
    pub fn index(id: ResourceID) usize {
        return @enumToInt(id);
    }

    /// An Another World game resource ID as represented in Another World's bytecode and GamePart definitions.
    pub const Raw = _Raw;
};
