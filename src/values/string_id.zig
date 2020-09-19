/// A raw string identifier as represented in Another World's bytecode and GamePart definitions.
/// This is not guaranteed to be valid, and must be looked up in a string table.
pub const Raw = u16;

pub const Error = error{
    /// Bytecode specified a string ID that was not found in the expected string table.
    InvalidStringID,
};
