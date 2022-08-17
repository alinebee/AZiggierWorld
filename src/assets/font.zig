//! This file defines the 8x8 fixed-width bitmap font used by Another World for displaying text.
//! The font bitmaps are taken from the original Another World MS-DOS release, and support
//! a subset of the full ASCII character set.

const anotherworld = @import("../lib/anotherworld.zig");

/// The width in pixels of each glyph.
pub const glyph_width: usize = @bitSizeOf(u8);
/// The height in pixels of each glyph.
pub const glyph_height: usize = 8;

/// An 8x8 pixel bitmap representing a single character in the font.
/// Glyphs are stored as arrays of 8 bytes, where each byte is a row along the Y axis
/// and each bit is a column along the X axis.
/// An "on" bit indicates to draw a pixel at that X, Y position.
pub const Glyph = [glyph_height]u8;

/// Given a UTF-8 character, returns the glyph bitmap associated with that character.
/// returns `error.InvalidCharacter` if that character is not supported.
pub fn glyph(character: u8) Error!Glyph {
    if (character < min_character or character > max_character) {
        return error.InvalidCharacter;
    }

    const index: usize = character - min_character;
    return all_glyphs[index];
}

pub const Error = error{
    /// The specified character does not exist in the font.
    InvalidCharacter,
};

/// The minimum supported UTF-8 codepoint.
const min_character: u8 = ' '; // 32 in UTF8/ASCII
/// The maximum supported UTF-8 codepoint.
const max_character: u8 = '~'; // 126 in UTF8/ASCII

// -- Glyph definitions --

/// An array of all supported glyph bitmaps from 32 to 126.
/// These are indexed by their ASCII codepoint - 32,
/// so the glyph for ' ' (32 in ASCII) is at index 0.
const all_glyphs = [_]Glyph{
    // These are not strings, but references to actual constants declared below.
    // @"constant_name" is Zig's syntax for referring to constants and variables
    // whose names contain illegal characters.
    @" ",
    @"!",
    @"\"",
    @"#",
    @"$",
    @"%",
    @"&",
    @"'",
    @"(",
    @")",
    @"*",
    @"+",
    @",",
    @"-",
    @".",
    @"/",
    @"0",
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    @":",
    @";",
    @"<",
    @"=",
    @">",
    @"?",
    @"@",
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    @"[",
    @"\\",
    @"]",
    @"^",
    underscore, // _ and @"_" are reserved in zig
    @"`",
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    @"{",
    @"|",
    @"}",
    @"~",
};

// These bitmaps were translated from the hardcoded hex values in the reference implementation:
// https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/staticres.cpp#L71
// (One of the joys of binary notation is making the pixel data squintably readable.)

const @" " = Glyph{
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
};

const @"!" = Glyph{
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00000000,
    0b00010000,
    0b00000000,
};

const @"\"" = Glyph{
    0b00101000,
    0b00101000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
};

const @"#" = Glyph{
    0b00000000,
    0b00100100,
    0b01111110,
    0b00100100,
    0b00100100,
    0b01111110,
    0b00100100,
    0b00000000,
};

const @"$" = Glyph{
    0b00001000,
    0b00111110,
    0b01001000,
    0b00111100,
    0b00010010,
    0b01111100,
    0b00010000,
    0b00000000,
};

const @"%" = Glyph{
    0b01000010,
    0b10100100,
    0b01001000,
    0b00010000,
    0b00100100,
    0b01001010,
    0b10000100,
    0b00000000,
};

const @"&" = Glyph{
    0b01100000,
    0b10010000,
    0b10010000,
    0b01110000,
    0b10001010,
    0b10000100,
    0b01111010,
    0b00000000,
};

const @"'" = Glyph{
    0b00001000,
    0b00001000,
    0b00010000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
};

const @"(" = Glyph{
    0b00000110,
    0b00001000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00001000,
    0b00000110,
    0b00000000,
};

const @")" = Glyph{
    0b11000000,
    0b00100000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00100000,
    0b11000000,
    0b00000000,
};

const @"*" = Glyph{
    0b00000000,
    0b01000100,
    0b00101000,
    0b00010000,
    0b00101000,
    0b01000100,
    0b00000000,
    0b00000000,
};

const @"+" = Glyph{
    0b00000000,
    0b00010000,
    0b00010000,
    0b01111100,
    0b00010000,
    0b00010000,
    0b00000000,
    0b00000000,
};

const @"," = Glyph{
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00010000,
    0b00010000,
    0b00100000,
};

const @"-" = Glyph{
    0b00000000,
    0b00000000,
    0b00000000,
    0b01111100,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
};

const @"." = Glyph{
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00010000,
    0b00101000,
    0b00010000,
    0b00000000,
};

const @"/" = Glyph{
    0b00000000,
    0b00000100,
    0b00001000,
    0b00010000,
    0b00100000,
    0b01000000,
    0b00000000,
    0b00000000,
};

const @"0" = Glyph{
    0b01111000,
    0b10000100,
    0b10001100,
    0b10010100,
    0b10100100,
    0b11000100,
    0b01111000,
    0b00000000,
};

const @"1" = Glyph{
    0b00010000,
    0b00110000,
    0b01010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b01111100,
    0b00000000,
};

const @"2" = Glyph{
    0b01111000,
    0b10000100,
    0b00000100,
    0b00001000,
    0b00110000,
    0b01000000,
    0b11111100,
    0b00000000,
};

const @"3" = Glyph{
    0b01111000,
    0b10000100,
    0b00000100,
    0b00111000,
    0b00000100,
    0b10000100,
    0b01111000,
    0b00000000,
};

const @"4" = Glyph{
    0b00001000,
    0b00011000,
    0b00101000,
    0b01001000,
    0b11111100,
    0b00001000,
    0b00001000,
    0b00000000,
};

const @"5" = Glyph{
    0b11111100,
    0b10000000,
    0b11111000,
    0b00000100,
    0b00000100,
    0b10000100,
    0b01111000,
    0b00000000,
};

const @"6" = Glyph{
    0b00111000,
    0b01000000,
    0b10000000,
    0b11111000,
    0b10000100,
    0b10000100,
    0b01111000,
    0b00000000,
};

const @"7" = Glyph{
    0b11111100,
    0b00000100,
    0b00000100,
    0b00001000,
    0b00010000,
    0b00100000,
    0b01000000,
    0b00000000,
};

const @"8" = Glyph{
    0b01111000,
    0b10000100,
    0b10000100,
    0b01111000,
    0b10000100,
    0b10000100,
    0b01111000,
    0b00000000,
};

const @"9" = Glyph{
    0b01111000,
    0b10000100,
    0b10000100,
    0b01111100,
    0b00000100,
    0b00001000,
    0b01110000,
    0b00000000,
};

const @":" = Glyph{
    0b00000000,
    0b00011000,
    0b00011000,
    0b00000000,
    0b00000000,
    0b00011000,
    0b00011000,
    0b00000000,
};

const @";" = Glyph{
    0b00000000,
    0b00000000,
    0b00011000,
    0b00011000,
    0b00000000,
    0b00010000,
    0b00010000,
    0b01100000,
};

const @"<" = Glyph{
    0b00000100,
    0b00001000,
    0b00010000,
    0b00100000,
    0b00010000,
    0b00001000,
    0b00000100,
    0b00000000,
};

const @"=" = Glyph{
    0b00000000,
    0b00000000,
    0b11111110,
    0b00000000,
    0b00000000,
    0b11111110,
    0b00000000,
    0b00000000,
};

const @">" = Glyph{
    0b00100000,
    0b00010000,
    0b00001000,
    0b00000100,
    0b00001000,
    0b00010000,
    0b00100000,
    0b00000000,
};

const @"?" = Glyph{
    0b01111100,
    0b10000010,
    0b00000010,
    0b00001100,
    0b00010000,
    0b00000000,
    0b00010000,
    0b00000000,
};

const @"@" = Glyph{
    0b00110000,
    0b00011000,
    0b00001100,
    0b00001100,
    0b00001100,
    0b00011000,
    0b00110000,
    0b00000000,
};

const A = Glyph{
    0b01111000,
    0b10000100,
    0b10000100,
    0b11111100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b00000000,
};

const B = Glyph{
    0b11111000,
    0b10000100,
    0b10000100,
    0b11111000,
    0b10000100,
    0b10000100,
    0b11111000,
    0b00000000,
};

const C = Glyph{
    0b01111000,
    0b10000100,
    0b10000000,
    0b10000000,
    0b10000000,
    0b10000100,
    0b01111000,
    0b00000000,
};

const D = Glyph{
    0b11111000,
    0b10000100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b11111000,
    0b00000000,
};

const E = Glyph{
    0b01111100,
    0b01000000,
    0b01000000,
    0b01111000,
    0b01000000,
    0b01000000,
    0b01111100,
    0b00000000,
};

const F = Glyph{
    0b11111100,
    0b10000000,
    0b10000000,
    0b11110000,
    0b10000000,
    0b10000000,
    0b10000000,
    0b00000000,
};

const G = Glyph{
    0b01111100,
    0b10000000,
    0b10000000,
    0b10001100,
    0b10000100,
    0b10000100,
    0b01111100,
    0b00000000,
};

const H = Glyph{
    0b10000100,
    0b10000100,
    0b10000100,
    0b11111100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b00000000,
};

const I = Glyph{
    0b01111100,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b01111100,
    0b00000000,
};

const J = Glyph{
    0b00000100,
    0b00000100,
    0b00000100,
    0b00000100,
    0b10000100,
    0b10000100,
    0b01111000,
    0b00000000,
};

const K = Glyph{
    0b10001100,
    0b10010000,
    0b10100000,
    0b11100000,
    0b10010000,
    0b10001000,
    0b10000100,
    0b00000000,
};

const L = Glyph{
    0b10000000,
    0b10000000,
    0b10000000,
    0b10000000,
    0b10000000,
    0b10000000,
    0b11111100,
    0b00000000,
};

const M = Glyph{
    0b10000010,
    0b11000110,
    0b10101010,
    0b10010010,
    0b10000010,
    0b10000010,
    0b10000010,
    0b00000000,
};

const N = Glyph{
    0b10000100,
    0b11000100,
    0b10100100,
    0b10010100,
    0b10001100,
    0b10000100,
    0b10000100,
    0b00000000,
};

const O = Glyph{
    0b01111000,
    0b10000100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b01111000,
    0b00000000,
};

const P = Glyph{
    0b11111000,
    0b10000100,
    0b10000100,
    0b11111000,
    0b10000000,
    0b10000000,
    0b10000000,
    0b00000000,
};

const Q = Glyph{
    0b01111000,
    0b10000100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b10001100,
    0b01111100,
    0b00000011,
};

const R = Glyph{
    0b11111000,
    0b10000100,
    0b10000100,
    0b11111000,
    0b10010000,
    0b10001000,
    0b10000100,
    0b00000000,
};

const S = Glyph{
    0b01111000,
    0b10000100,
    0b10000000,
    0b01111000,
    0b00000100,
    0b10000100,
    0b01111000,
    0b00000000,
};

const T = Glyph{
    0b01111100,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00000000,
};

const U = Glyph{
    0b10000100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b01111000,
    0b00000000,
};

const V = Glyph{
    0b10000100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b10000100,
    0b01001000,
    0b00110000,
    0b00000000,
};

const W = Glyph{
    0b10000010,
    0b10000010,
    0b10000010,
    0b10000010,
    0b10010010,
    0b10101010,
    0b11000110,
    0b00000000,
};

const X = Glyph{
    0b10000010,
    0b01000100,
    0b00101000,
    0b00010000,
    0b00101000,
    0b01000100,
    0b10000010,
    0b00000000,
};

const Y = Glyph{
    0b10000010,
    0b01000100,
    0b00101000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00000000,
};

const Z = Glyph{
    0b11111100,
    0b00000100,
    0b00001000,
    0b00010000,
    0b00100000,
    0b01000000,
    0b11111100,
    0b00000000,
};

const @"[" = Glyph{
    0b00111100,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00111100,
    0b00000000,
};

const @"\\" = Glyph{
    0b00111100,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00111100,
    0b00000000,
};

const @"]" = Glyph{
    0b00111100,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00111100,
    0b00000000,
};

const @"^" = Glyph{
    0b00111100,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00111100,
    0b00000000,
};

const underscore = Glyph{
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b11111110,
};

const @"`" = Glyph{
    0b00111100,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00110000,
    0b00111100,
    0b00000000,
};

const a = Glyph{
    0b00000000,
    0b00000000,
    0b00111000,
    0b00000100,
    0b00111100,
    0b01000100,
    0b00111100,
    0b00000000,
};

const b = Glyph{
    0b01000000,
    0b01000000,
    0b01111000,
    0b01000100,
    0b01000100,
    0b01000100,
    0b01111000,
    0b00000000,
};

const c = Glyph{
    0b00000000,
    0b00000000,
    0b00111100,
    0b01000000,
    0b01000000,
    0b01000000,
    0b00111100,
    0b00000000,
};

const d = Glyph{
    0b00000100,
    0b00000100,
    0b00111100,
    0b01000100,
    0b01000100,
    0b01000100,
    0b00111100,
    0b00000000,
};

const e = Glyph{
    0b00000000,
    0b00000000,
    0b00111000,
    0b01000100,
    0b01111100,
    0b01000000,
    0b00111100,
    0b00000000,
};

const f = Glyph{
    0b00111000,
    0b01000100,
    0b01000000,
    0b01100000,
    0b01000000,
    0b01000000,
    0b01000000,
    0b00000000,
};

const g = Glyph{
    0b00000000,
    0b00000000,
    0b00111100,
    0b01000100,
    0b01000100,
    0b00111100,
    0b00000100,
    0b01111000,
};

const h = Glyph{
    0b01000000,
    0b01000000,
    0b01011000,
    0b01100100,
    0b01000100,
    0b01000100,
    0b01000100,
    0b00000000,
};

const i = Glyph{
    0b00010000,
    0b00000000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00000000,
};

const j = Glyph{
    0b00000010,
    0b00000000,
    0b00000010,
    0b00000010,
    0b00000010,
    0b00000010,
    0b01000010,
    0b00111100,
};

const k = Glyph{
    0b01000000,
    0b01000000,
    0b01000110,
    0b01001000,
    0b01110000,
    0b01001000,
    0b01000110,
    0b00000000,
};

const l = Glyph{
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00000000,
};

const m = Glyph{
    0b00000000,
    0b00000000,
    0b11101100,
    0b10010010,
    0b10010010,
    0b10010010,
    0b10010010,
    0b00000000,
};

const n = Glyph{
    0b00000000,
    0b00000000,
    0b01111000,
    0b01000100,
    0b01000100,
    0b01000100,
    0b01000100,
    0b00000000,
};

const o = Glyph{
    0b00000000,
    0b00000000,
    0b00111000,
    0b01000100,
    0b01000100,
    0b01000100,
    0b00111000,
    0b00000000,
};

const p = Glyph{
    0b00000000,
    0b00000000,
    0b01111000,
    0b01000100,
    0b01000100,
    0b01111000,
    0b01000000,
    0b01000000,
};

const q = Glyph{
    0b00000000,
    0b00000000,
    0b00111100,
    0b01000100,
    0b01000100,
    0b00111100,
    0b00000100,
    0b00000100,
};

const r = Glyph{
    0b00000000,
    0b00000000,
    0b01001100,
    0b01110000,
    0b01000000,
    0b01000000,
    0b01000000,
    0b00000000,
};

const s = Glyph{
    0b00000000,
    0b00000000,
    0b00111100,
    0b01000000,
    0b00111000,
    0b00000100,
    0b01111000,
    0b00000000,
};

const t = Glyph{
    0b00010000,
    0b00010000,
    0b00111100,
    0b00010000,
    0b00010000,
    0b00010000,
    0b00001100,
    0b00000000,
};

const u = Glyph{
    0b00000000,
    0b00000000,
    0b01000100,
    0b01000100,
    0b01000100,
    0b01000100,
    0b01111000,
    0b00000000,
};

const v = Glyph{
    0b00000000,
    0b00000000,
    0b01000100,
    0b01000100,
    0b01000100,
    0b00101000,
    0b00010000,
    0b00000000,
};

const w = Glyph{
    0b00000000,
    0b00000000,
    0b10000010,
    0b10000010,
    0b10010010,
    0b10101010,
    0b11000110,
    0b00000000,
};

const x = Glyph{
    0b00000000,
    0b00000000,
    0b01000100,
    0b00101000,
    0b00010000,
    0b00101000,
    0b01000100,
    0b00000000,
};

const y = Glyph{
    0b00000000,
    0b00000000,
    0b01000010,
    0b00100010,
    0b00100100,
    0b00011000,
    0b00001000,
    0b00110000,
};

const z = Glyph{
    0b00000000,
    0b00000000,
    0b01111100,
    0b00001000,
    0b00010000,
    0b00100000,
    0b01111100,
    0b00000000,
};

const @"{" = Glyph{
    0b01100000,
    0b10010000,
    0b00100000,
    0b01000000,
    0b11110000,
    0b00000000,
    0b00000000,
    0b00000000,
};

const @"|" = Glyph{
    0b11111110,
    0b11111110,
    0b11111110,
    0b11111110,
    0b11111110,
    0b11111110,
    0b11111110,
    0b00000000,
};

const @"}" = Glyph{
    0b00111000,
    0b01000100,
    0b10111010,
    0b10100010,
    0b10111010,
    0b01000100,
    0b00111000,
    0b00000000,
};

const @"~" = Glyph{
    0b00111000,
    0b01000100,
    0b10000010,
    0b10000010,
    0b01000100,
    0b00101000,
    0b11101110,
    0b00000000,
};

// -- Tests --

const testing = anotherworld.testing;

// zig fmt: off
test "glyph returns correct glyphs for supported characters" {
    try testing.expectEqual(@" ",   glyph(' '));
    try testing.expectEqual(@"!",   glyph('!'));
    try testing.expectEqual(@"\"",  glyph('"'));
    try testing.expectEqual(@"#",   glyph('#'));
    try testing.expectEqual(@"$",   glyph('$'));
    try testing.expectEqual(@"%",   glyph('%'));
    try testing.expectEqual(@"&",   glyph('&'));
    try testing.expectEqual(@"'",   glyph('\''));
    try testing.expectEqual(@"(",   glyph('('));
    try testing.expectEqual(@")",   glyph(')'));
    try testing.expectEqual(@"*",   glyph('*'));
    try testing.expectEqual(@"+",   glyph('+'));
    try testing.expectEqual(@",",   glyph(','));
    try testing.expectEqual(@"-",   glyph('-'));
    try testing.expectEqual(@".",   glyph('.'));
    try testing.expectEqual(@"/",   glyph('/'));
    try testing.expectEqual(@"0",   glyph('0'));
    try testing.expectEqual(@"1",   glyph('1'));
    try testing.expectEqual(@"2",   glyph('2'));
    try testing.expectEqual(@"3",   glyph('3'));
    try testing.expectEqual(@"4",   glyph('4'));
    try testing.expectEqual(@"5",   glyph('5'));
    try testing.expectEqual(@"6",   glyph('6'));
    try testing.expectEqual(@"7",   glyph('7'));
    try testing.expectEqual(@"8",   glyph('8'));
    try testing.expectEqual(@"9",   glyph('9'));
    try testing.expectEqual(@":",   glyph(':'));
    try testing.expectEqual(@";",   glyph(';'));
    try testing.expectEqual(@"<",   glyph('<'));
    try testing.expectEqual(@"=",   glyph('='));
    try testing.expectEqual(@">",   glyph('>'));
    try testing.expectEqual(@"?",   glyph('?'));
    try testing.expectEqual(@"@",   glyph('@'));
    try testing.expectEqual(A,      glyph('A'));
    try testing.expectEqual(B,      glyph('B'));
    try testing.expectEqual(C,      glyph('C'));
    try testing.expectEqual(D,      glyph('D'));
    try testing.expectEqual(E,      glyph('E'));
    try testing.expectEqual(F,      glyph('F'));
    try testing.expectEqual(G,      glyph('G'));
    try testing.expectEqual(H,      glyph('H'));
    try testing.expectEqual(I,      glyph('I'));
    try testing.expectEqual(J,      glyph('J'));
    try testing.expectEqual(K,      glyph('K'));
    try testing.expectEqual(L,      glyph('L'));
    try testing.expectEqual(M,      glyph('M'));
    try testing.expectEqual(N,      glyph('N'));
    try testing.expectEqual(O,      glyph('O'));
    try testing.expectEqual(P,      glyph('P'));
    try testing.expectEqual(Q,      glyph('Q'));
    try testing.expectEqual(R,      glyph('R'));
    try testing.expectEqual(S,      glyph('S'));
    try testing.expectEqual(T,      glyph('T'));
    try testing.expectEqual(U,      glyph('U'));
    try testing.expectEqual(V,      glyph('V'));
    try testing.expectEqual(W,      glyph('W'));
    try testing.expectEqual(X,      glyph('X'));
    try testing.expectEqual(Y,      glyph('Y'));
    try testing.expectEqual(Z,      glyph('Z'));
    try testing.expectEqual(@"[",   glyph('['));
    try testing.expectEqual(@"\\",  glyph('\\'));
    try testing.expectEqual(@"]",   glyph(']'));
    try testing.expectEqual(@"^",   glyph('^'));
    try testing.expectEqual(underscore, glyph('_'));
    try testing.expectEqual(@"`",   glyph('`'));
    try testing.expectEqual(a,      glyph('a'));
    try testing.expectEqual(b,      glyph('b'));
    try testing.expectEqual(c,      glyph('c'));
    try testing.expectEqual(d,      glyph('d'));
    try testing.expectEqual(e,      glyph('e'));
    try testing.expectEqual(f,      glyph('f'));
    try testing.expectEqual(g,      glyph('g'));
    try testing.expectEqual(h,      glyph('h'));
    try testing.expectEqual(i,      glyph('i'));
    try testing.expectEqual(j,      glyph('j'));
    try testing.expectEqual(k,      glyph('k'));
    try testing.expectEqual(l,      glyph('l'));
    try testing.expectEqual(m,      glyph('m'));
    try testing.expectEqual(n,      glyph('n'));
    try testing.expectEqual(o,      glyph('o'));
    try testing.expectEqual(p,      glyph('p'));
    try testing.expectEqual(q,      glyph('q'));
    try testing.expectEqual(r,      glyph('r'));
    try testing.expectEqual(s,      glyph('s'));
    try testing.expectEqual(t,      glyph('t'));
    try testing.expectEqual(u,      glyph('u'));
    try testing.expectEqual(v,      glyph('v'));
    try testing.expectEqual(w,      glyph('w'));
    try testing.expectEqual(x,      glyph('x'));
    try testing.expectEqual(y,      glyph('y'));
    try testing.expectEqual(z,      glyph('z'));
    try testing.expectEqual(@"{",   glyph('{'));
    try testing.expectEqual(@"|",   glyph('|'));
    try testing.expectEqual(@"}",   glyph('}'));
    try testing.expectEqual(@"~",   glyph('~'));
}
// zig fmt: on

test "glyph returns error.InvalidCharacter for out-of-range characters" {
    try testing.expectError(error.InvalidCharacter, glyph(0x00));
    try testing.expectError(error.InvalidCharacter, glyph('\n'));
    try testing.expectError(error.InvalidCharacter, glyph(0x7F));
    try testing.expectError(error.InvalidCharacter, glyph(0xFF));
}
