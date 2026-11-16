# Approximate text metrics (Helvetica/Arial advance widths, in 1/1000 em).

const _HELV = Dict{Char,Int}(
    ' ' => 278, '!' => 278, '"' => 355, '#' => 556, '$' => 556, '%' => 889, '&' => 667, '\'' => 191,
    '(' => 333, ')' => 333, '*' => 389, '+' => 584, ',' => 278, '-' => 333, '.' => 278, '/' => 278,
    '0' => 556, '1' => 556, '2' => 556, '3' => 556, '4' => 556, '5' => 556, '6' => 556, '7' => 556,
    '8' => 556, '9' => 556, ':' => 278, ';' => 278, '<' => 584, '=' => 584, '>' => 584, '?' => 556,
    '@' => 1015, 'A' => 667, 'B' => 667, 'C' => 722, 'D' => 722, 'E' => 667, 'F' => 611, 'G' => 778,
    'H' => 722, 'I' => 278, 'J' => 500, 'K' => 667, 'L' => 556, 'M' => 833, 'N' => 722, 'O' => 778,
    'P' => 667, 'Q' => 778, 'R' => 722, 'S' => 667, 'T' => 611, 'U' => 722, 'V' => 667, 'W' => 944,
    'X' => 667, 'Y' => 667, 'Z' => 611, '[' => 278, '\\' => 278, ']' => 278, '^' => 469, '_' => 556,
    '`' => 333, 'a' => 556, 'b' => 556, 'c' => 500, 'd' => 556, 'e' => 556, 'f' => 278, 'g' => 556,
    'h' => 556, 'i' => 222, 'j' => 222, 'k' => 500, 'l' => 222, 'm' => 833, 'n' => 556, 'o' => 556,
    'p' => 556, 'q' => 556, 'r' => 333, 's' => 500, 't' => 278, 'u' => 556, 'v' => 500, 'w' => 722,
    'x' => 500, 'y' => 500, 'z' => 500, '{' => 334, '|' => 260, '}' => 334, '~' => 584,
    '–' => 556, '—' => 1000, '×' => 584, '−' => 584, '≥' => 549, '≤' => 549, '±' => 584, '°' => 400,
    '…' => 1000, '·' => 278, 'µ' => 556, 'é' => 556, 'è' => 556, 'ë' => 556, 'ü' => 556, 'ö' => 556,
)

# Helvetica-Bold differs mostly in lower case; scale per class
function _charwidth(c::Char, bold::Bool)
    w = get(_HELV, c, 0)
    if w == 0
        w = c < '⺀' ? 556 : 1000       # wide CJK and friends
    end
    if bold
        w = islowercase(c) ? round(Int, w * 1.09) : isuppercase(c) ? round(Int, w * 1.06) : w
    end
    return w
end

"""
    textwidth_px(s, fontsize; bold=false) -> Float64

Approximate rendered width of `s` in pixels for a Helvetica-like font.
"""
function textwidth_px(s::AbstractString, fs::Real; bold::Bool=false)
    w = 0
    for c in s
        w += _charwidth(c, bold)
    end
    return w * fs / 1000
end

charwidth_px(c::Char, fs::Real; bold::Bool=false) = _charwidth(c, bold) * fs / 1000
