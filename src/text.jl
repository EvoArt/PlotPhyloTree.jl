# Text metrics. Layout needs label widths before anything is drawn; they come
# from a `FontMetrics` table of advance widths (1/1000 em). Tables for common
# fonts are bundled (fontdata.jl); `fontmetrics(path)` reads any OpenType or
# TrueType file, so the layout can match the font a LaTeX or Typst document
# will set the labels in.

"""
    FontMetrics

Advance widths of a font (regular, bold and italic), in 1/1000 em. Make one
with [`fontmetrics`](@ref), or name a bundled one: `:helvetica` (also
Arial), `:lmroman` and `:lmsans` (Latin Modern, LaTeX's default), `:times`.
"""
struct FontMetrics
    name::String
    regular::Dict{Char,Float64}
    bold::Dict{Char,Float64}
    italic::Dict{Char,Float64}
    bolditalic::Dict{Char,Float64}
    default::Float64                 # width of a character the font lacks
end

function Base.show(io::IO, m::FontMetrics)
    print(io, "FontMetrics(\"", m.name, "\", ", length(m.regular), " characters)")
end

_table(m::FontMetrics, bold::Bool, italic::Bool) =
    bold ? (italic ? m.bolditalic : m.bold) : (italic ? m.italic : m.regular)

# --- reading OpenType/TrueType files -------------------------------------------------------

_u16(b, i) = (UInt16(b[i+1]) << 8) | b[i+2]                          # i: 0-based offset
_i16(b, i) = reinterpret(Int16, _u16(b, i))
_u32(b, i) = (UInt32(_u16(b, i)) << 16) | _u16(b, i + 2)

function _sfnttables(b::Vector{UInt8})
    tag = String(b[1:4])
    tag == "ttcf" && throw(ArgumentError("font collections (.ttc) are not supported; use a single .ttf/.otf"))
    n = _u16(b, 4)
    tabs = Dict{String,Int}()
    for k in 0:n-1
        rec = 12 + 16k
        tabs[String(b[rec+1:rec+4])] = Int(_u32(b, rec + 8))
    end
    return tabs
end

# Unicode code point -> glyph id, from the best cmap subtable (format 12 or 4)
function _cmap(b::Vector{UInt8}, off::Int)
    n = _u16(b, off + 2)
    best = (-1, 0)
    for k in 0:n-1
        rec = off + 4 + 8k
        plat, enc = _u16(b, rec), _u16(b, rec + 2)
        sub = off + Int(_u32(b, rec + 4))
        fmt = _u16(b, sub)
        score = fmt == 12 ? 3 : (fmt == 4 && (plat == 3 && enc == 1 || plat == 0)) ? 2 : -1
        score > best[1] && (best = (score, sub))
    end
    best[1] < 0 && throw(ArgumentError("font has no Unicode character map"))
    sub = best[2]
    map = Dict{UInt32,Int}()
    if _u16(b, sub) == 12
        ng = _u32(b, sub + 12)
        for g in 0:ng-1
            r = sub + 16 + 12g
            c0, c1, g0 = _u32(b, r), _u32(b, r + 4), _u32(b, r + 8)
            c1 - c0 > 0x3000 && (c1 = c0 + 0x3000)          # skip huge CJK ranges
            for c in c0:c1
                map[c] = Int(g0 + (c - c0))
            end
        end
    else
        segx2 = _u16(b, sub + 6)
        ends = sub + 14
        starts = ends + segx2 + 2
        deltas = starts + segx2
        ranges = deltas + segx2
        for s in 0:2:segx2-2
            c0, c1 = _u16(b, starts + s), _u16(b, ends + s)
            δ, ro = _u16(b, deltas + s), _u16(b, ranges + s)
            c0 == 0xffff && continue
            for c in c0:c1
                g = if ro == 0
                    (c + δ) & 0xffff
                else
                    gi = ranges + s + ro + 2 * (c - c0)
                    v = _u16(b, gi)
                    v == 0 ? 0 : (v + δ) & 0xffff
                end
                g == 0 || (map[UInt32(c)] = Int(g))
            end
        end
    end
    return map
end

# advance widths (1/1000 em) of the characters the font maps
function _sfntwidths(path::AbstractString)
    b = read(path)
    tabs = _sfnttables(b)
    for t in ("head", "hhea", "hmtx", "cmap")
        haskey(tabs, t) || throw(ArgumentError("$path has no '$t' table; is it a font file?"))
    end
    upem = _u16(b, tabs["head"] + 18)
    nh = _u16(b, tabs["hhea"] + 34)
    hm = tabs["hmtx"]
    adv(g) = _u16(b, hm + 4 * min(g, nh - 1))
    w = Dict{Char,Float64}()
    for (c, g) in _cmap(b, tabs["cmap"])
        isvalid(Char, c) || continue
        w[Char(c)] = round(1000 * adv(g) / upem; digits=1)
    end
    return w
end

"""
    fontmetrics(regular; bold=nothing, italic=nothing, bolditalic=nothing, name=…) -> FontMetrics

Read advance widths from OpenType/TrueType font files (`.otf`, `.ttf`), so
the layout sizes labels for that font. Missing styles are estimated from the
regular widths (bold 6 % wider). Pass the result to `treeplot(…; metrics=…)`.

```julia
m = fontmetrics("C:/Windows/Fonts/calibri.ttf"; bold="C:/Windows/Fonts/calibrib.ttf")
p = treeplot(tree; metrics=m)
```
"""
function fontmetrics(regular::AbstractString; bold=nothing, italic=nothing, bolditalic=nothing,
                     name::AbstractString=splitext(basename(regular))[1])
    r = _sfntwidths(regular)
    b = bold === nothing ? Dict(c => 1.06w for (c, w) in r) : _sfntwidths(bold)
    i = italic === nothing ? r : _sfntwidths(italic)
    bi = bolditalic !== nothing ? _sfntwidths(bolditalic) : italic === nothing ? b : Dict(c => 1.06w for (c, w) in i)
    return FontMetrics(String(name), r, b, i, bi, get(r, 'n', 500.0))
end

# --- the metrics in use ----------------------------------------------------------------

include("fontdata.jl")

"""Look up bundled metrics by name; `nothing` and font lists pick by family."""
function _metrics(m)
    m isa FontMetrics && return m
    m isa Symbol || throw(ArgumentError("metrics must be a FontMetrics or one of $(collect(keys(BUNDLED_METRICS)))"))
    m === :arial && (m = :helvetica)
    haskey(BUNDLED_METRICS, m) ||
        throw(ArgumentError("unknown metrics :$m; choose from $(collect(keys(BUNDLED_METRICS))) or use fontmetrics(path)"))
    return BUNDLED_METRICS[m]
end

# bundled metrics for the first family in a CSS-style font list that we know
function _metricsforfont(font::AbstractString)
    for f in split(lowercase(font), ',')
        f = strip(strip(f), ['"', '\''])
        (occursin("latin modern sans", f) || f in ("lmsans", "cmss", "computer modern sans")) && return :lmsans
        (occursin("latin modern", f) || occursin("computer modern", f) || f in ("lmroman", "cmr", "new computer modern")) &&
            return :lmroman
        (occursin("times", f) || occursin("termes", f) || f == "serif") && return :times
        (occursin("helvetica", f) || occursin("arial", f) || occursin("heros", f) || f == "sans-serif") && return :helvetica
    end
    return :helvetica
end

const _CURRENT = Ref{FontMetrics}()

"""Run `f` with `m` as the metrics used by `textwidth_px`."""
function withmetrics(f, m::FontMetrics)
    old = isassigned(_CURRENT) ? _CURRENT[] : nothing
    _CURRENT[] = m
    try
        return f()
    finally
        old === nothing ? (_CURRENT[] = BUNDLED_METRICS[:helvetica]) : (_CURRENT[] = old)
    end
end
currentmetrics() = isassigned(_CURRENT) ? _CURRENT[] : BUNDLED_METRICS[:helvetica]

function _charwidth(m::FontMetrics, c::Char, bold::Bool, italic::Bool)
    w = get(_table(m, bold, italic), c, NaN)
    isnan(w) || return w
    # a character the font lacks: Helvetica's width scaled to this font, or a CJK em
    h = get(_HELV, c, 0)
    h == 0 && return c < '⺀' ? m.default : 1000.0
    return h * m.default / 556
end

"""
    textwidth_px(s, fontsize; bold=false, italic=false) -> Float64

Width of `s` in px at `fontsize`, using the metrics of the plot being laid
out (Helvetica outside a layout).
"""
function textwidth_px(s::AbstractString, fs::Real; bold::Bool=false, italic::Bool=false)
    m = currentmetrics()
    w = 0.0
    for c in s
        w += _charwidth(m, c, bold, italic)
    end
    return w * fs / 1000
end

charwidth_px(c::Char, fs::Real; bold::Bool=false, italic::Bool=false) =
    _charwidth(currentmetrics(), c, bold, italic) * fs / 1000
