/// An 8x8 pixel bitmap representing a single character in the font,
/// where each "on"-bit represents a pixel that will be drawn in the current color.
pub const Glyph = [8]u8;

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

const all_glyphs = [_]Glyph{
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

const testing = @import("../utils/testing.zig");

// zig fmt: off
test "glyph returns correct glyphs for supported characters" {
    testing.expectEqual(@" ",   glyph(' '));
    testing.expectEqual(@"!",   glyph('!'));
    testing.expectEqual(@"\"",  glyph('"'));
    testing.expectEqual(@"#",   glyph('#'));
    testing.expectEqual(@"$",   glyph('$'));
    testing.expectEqual(@"%",   glyph('%'));
    testing.expectEqual(@"&",   glyph('&'));
    testing.expectEqual(@"'",   glyph('\''));
    testing.expectEqual(@"(",   glyph('('));
    testing.expectEqual(@")",   glyph(')'));
    testing.expectEqual(@"*",   glyph('*'));
    testing.expectEqual(@"+",   glyph('+'));
    testing.expectEqual(@",",   glyph(','));
    testing.expectEqual(@"-",   glyph('-'));
    testing.expectEqual(@".",   glyph('.'));
    testing.expectEqual(@"/",   glyph('/'));
    testing.expectEqual(@"0",   glyph('0'));
    testing.expectEqual(@"1",   glyph('1'));
    testing.expectEqual(@"2",   glyph('2'));
    testing.expectEqual(@"3",   glyph('3'));
    testing.expectEqual(@"4",   glyph('4'));
    testing.expectEqual(@"5",   glyph('5'));
    testing.expectEqual(@"6",   glyph('6'));
    testing.expectEqual(@"7",   glyph('7'));
    testing.expectEqual(@"8",   glyph('8'));
    testing.expectEqual(@"9",   glyph('9'));
    testing.expectEqual(@":",   glyph(':'));
    testing.expectEqual(@";",   glyph(';'));
    testing.expectEqual(@"<",   glyph('<'));
    testing.expectEqual(@"=",   glyph('='));
    testing.expectEqual(@">",   glyph('>'));
    testing.expectEqual(@"?",   glyph('?'));
    testing.expectEqual(@"@",   glyph('@'));
    testing.expectEqual(A,      glyph('A'));
    testing.expectEqual(B,      glyph('B'));
    testing.expectEqual(C,      glyph('C'));
    testing.expectEqual(D,      glyph('D'));
    testing.expectEqual(E,      glyph('E'));
    testing.expectEqual(F,      glyph('F'));
    testing.expectEqual(G,      glyph('G'));
    testing.expectEqual(H,      glyph('H'));
    testing.expectEqual(I,      glyph('I'));
    testing.expectEqual(J,      glyph('J'));
    testing.expectEqual(K,      glyph('K'));
    testing.expectEqual(L,      glyph('L'));
    testing.expectEqual(M,      glyph('M'));
    testing.expectEqual(N,      glyph('N'));
    testing.expectEqual(O,      glyph('O'));
    testing.expectEqual(P,      glyph('P'));
    testing.expectEqual(Q,      glyph('Q'));
    testing.expectEqual(R,      glyph('R'));
    testing.expectEqual(S,      glyph('S'));
    testing.expectEqual(T,      glyph('T'));
    testing.expectEqual(U,      glyph('U'));
    testing.expectEqual(V,      glyph('V'));
    testing.expectEqual(W,      glyph('W'));
    testing.expectEqual(X,      glyph('X'));
    testing.expectEqual(Y,      glyph('Y'));
    testing.expectEqual(Z,      glyph('Z'));
    testing.expectEqual(@"[",   glyph('['));
    testing.expectEqual(@"\\",  glyph('\\'));
    testing.expectEqual(@"]",   glyph(']'));
    testing.expectEqual(@"^",   glyph('^'));
    testing.expectEqual(underscore, glyph('_'));
    testing.expectEqual(@"`",   glyph('`'));
    testing.expectEqual(a,      glyph('a'));
    testing.expectEqual(b,      glyph('b'));
    testing.expectEqual(c,      glyph('c'));
    testing.expectEqual(d,      glyph('d'));
    testing.expectEqual(e,      glyph('e'));
    testing.expectEqual(f,      glyph('f'));
    testing.expectEqual(g,      glyph('g'));
    testing.expectEqual(h,      glyph('h'));
    testing.expectEqual(i,      glyph('i'));
    testing.expectEqual(j,      glyph('j'));
    testing.expectEqual(k,      glyph('k'));
    testing.expectEqual(l,      glyph('l'));
    testing.expectEqual(m,      glyph('m'));
    testing.expectEqual(n,      glyph('n'));
    testing.expectEqual(o,      glyph('o'));
    testing.expectEqual(p,      glyph('p'));
    testing.expectEqual(q,      glyph('q'));
    testing.expectEqual(r,      glyph('r'));
    testing.expectEqual(s,      glyph('s'));
    testing.expectEqual(t,      glyph('t'));
    testing.expectEqual(u,      glyph('u'));
    testing.expectEqual(v,      glyph('v'));
    testing.expectEqual(w,      glyph('w'));
    testing.expectEqual(x,      glyph('x'));
    testing.expectEqual(y,      glyph('y'));
    testing.expectEqual(z,      glyph('z'));
    testing.expectEqual(@"{",   glyph('{'));
    testing.expectEqual(@"|",   glyph('|'));
    testing.expectEqual(@"}",   glyph('}'));
    testing.expectEqual(@"~",   glyph('~'));
}
// zig fmt: on

test "glyph returns error.InvalidCharacter for out-of-range characters" {
    testing.expectError(error.InvalidCharacter, glyph(0x00));
    testing.expectError(error.InvalidCharacter, glyph('\n'));
    testing.expectError(error.InvalidCharacter, glyph(0x7F));
    testing.expectError(error.InvalidCharacter, glyph(0xFF));
}
