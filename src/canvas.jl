# A backend-neutral canvas: drawing calls record primitives (paths made of
# move/line/arc/close segments, rectangles, circles, text, images, groups) and
# track the bounding box of what is drawn. Each backend (SVG, TikZ, CeTZ,
# Makie) translates the recorded primitives; all layout happens before that.
#
# Coordinates are screen-like: x to the right, y downwards, angles in radians
# clockwise from +x (text angles in degrees, also clockwise). Lengths are px;
# backends with physical units read 1 px as 1 bp/pt.

mutable struct BBox
    xmin::Float64
    ymin::Float64
    xmax::Float64
    ymax::Float64
end
BBox() = BBox(Inf, Inf, -Inf, -Inf)
isempty_bbox(b::BBox) = b.xmin > b.xmax

function grow!(b::BBox, x::Real, y::Real)
    (isfinite(x) && isfinite(y)) || return b
    b.xmin = min(b.xmin, x); b.xmax = max(b.xmax, x)
    b.ymin = min(b.ymin, y); b.ymax = max(b.ymax, y)
    return b
end
grow!(b::BBox, o::BBox) = isempty_bbox(o) ? b : (grow!(b, o.xmin, o.ymin); grow!(b, o.xmax, o.ymax))

# --- primitives ------------------------------------------------------------------------

"""
Path segment. `op` is `'M'` (move to `x, y`), `'L'` (line to `x, y`), `'A'`
(circular arc around `cx, cy` with radius `r` from angle `a1` to `a2`, ending
at `x, y`) or `'Z'` (close the subpath).
"""
struct Seg
    op::Char
    x::Float64
    y::Float64
    cx::Float64
    cy::Float64
    r::Float64
    a1::Float64
    a2::Float64
end
Seg(op::Char, x, y) = Seg(op, x, y, 0.0, 0.0, 0.0, 0.0, 0.0)

abstract type Prim end

struct PathPrim <: Prim
    segs::Vector{Seg}
    fill::RGBA
    stroke::RGBA
    linewidth::Float64
    dash::Any                       # nothing, :solid, :dash, :dot, :dashdot, a string or a vector
    cap::String                     # "round", "butt", "square"
    join::String                    # "round", "miter", "bevel"
    fillrule::Union{Nothing,String}
    class::String
end

struct RectPrim <: Prim
    x::Float64
    y::Float64
    w::Float64
    h::Float64
    fill::RGBA
    stroke::RGBA
    linewidth::Float64
    rx::Float64
    class::String
    gradient::Vector{RGBA}          # left-to-right colour stops (evenly spaced) instead of `fill`
end

struct CirclePrim <: Prim
    x::Float64
    y::Float64
    r::Float64
    fill::RGBA
    stroke::RGBA
    linewidth::Float64
end

struct TextPrim <: Prim
    x::Float64
    y::Float64
    text::String
    fontsize::Float64
    angle::Float64                  # degrees, clockwise
    halign::Symbol                  # :left, :center, :right
    valign::Symbol                  # :center, :baseline, :top, :bottom
    color::RGBA
    bold::Bool
    italic::Bool
    family::Union{Nothing,String}
    halo::RGBA
    halowidth::Float64
    class::String
end

struct ImagePrim <: Prim
    x::Float64
    y::Float64
    w::Float64
    h::Float64
    src::String                     # URL/data URI, or SVG markup when `svg`
    svg::Bool
    opacity::Float64
end

struct GroupPrim <: Prim
    class::String
    children::Vector{Prim}
end

mutable struct Canvas
    prims::Vector{Prim}
    stack::Vector{Vector{Prim}}
    bbox::BBox
end
Canvas() = (v = Prim[]; Canvas(v, [v], BBox()))

_push!(c::Canvas, p::Prim) = (push!(last(c.stack), p); p)

function group(f, c::Canvas, class::AbstractString="")
    g = GroupPrim(String(class), Prim[])
    _push!(c, g)
    push!(c.stack, g.children)
    try
        f()
    finally
        pop!(c.stack)
    end
    return g
end

"""Visit every primitive (groups flattened) in drawing order."""
function foreachprim(f, prims::Vector{Prim})
    for p in prims
        p isa GroupPrim ? foreachprim(f, p.children) : f(p)
    end
end

# dash spec -> on/off lengths in px
function _dashvec(dash, lw)
    (dash === nothing || dash === :solid) && return Float64[]
    dash === :dash && return [4lw + 2, 2lw + 2]
    dash === :dot && return [0.01, 2lw + 1.5]
    dash === :dashdot && return [4lw + 2, 2lw + 1, 0.01, 2lw + 1]
    dash isa AbstractString && return [parse(Float64, s) for s in split(dash, r"[\s,]+"; keepempty=false)]
    dash isa AbstractVector && return Float64.(dash)
    throw(ArgumentError("linestyle must be :solid, :dash, :dot, :dashdot or a dash vector"))
end

# --- paths -------------------------------------------------------------------------

"""Incrementally built path with bounding-box tracking."""
mutable struct PathBuilder
    segs::Vector{Seg}
    bbox::BBox
    x::Float64
    y::Float64
end
PathBuilder() = PathBuilder(Seg[], BBox(), 0.0, 0.0)

function M!(pb::PathBuilder, x, y)
    push!(pb.segs, Seg('M', x, y))
    pb.x = x; pb.y = y
    grow!(pb.bbox, x, y)
    return pb
end
function L!(pb::PathBuilder, x, y)
    push!(pb.segs, Seg('L', x, y))
    pb.x = x; pb.y = y
    grow!(pb.bbox, x, y)
    return pb
end
Z!(pb::PathBuilder) = (push!(pb.segs, Seg('Z', pb.x, pb.y)); pb)

# circular arc around (cx, cy) with radius r from angle a1 to a2 (radians, screen
# coordinates, positive = clockwise); the pen must already be at the start
function arc!(pb::PathBuilder, cx, cy, r, a1, a2)
    r <= 1e-9 && return L!(pb, cx, cy)
    Δ = a2 - a1
    abs(Δ) < 1e-12 && return pb
    if abs(Δ) > 2π - 1e-6          # split full circles
        mid = a1 + Δ / 2
        arc!(pb, cx, cy, r, a1, mid)
        return arc!(pb, cx, cy, r, mid, a2)
    end
    x2 = cx + r * cos(a2); y2 = cy + r * sin(a2)
    push!(pb.segs, Seg('A', x2, y2, cx, cy, r, a1, a2))
    # bounding box: sample the arc
    n = max(2, ceil(Int, abs(Δ) / (π / 18)))
    for k in 0:n
        a = a1 + Δ * k / n
        grow!(pb.bbox, cx + r * cos(a), cy + r * sin(a))
    end
    pb.x = x2; pb.y = y2
    return pb
end

function path!(c::Canvas, pb::PathBuilder; fill=TRANSPARENT, stroke=TRANSPARENT, linewidth=1.0,
               dash=nothing, cap="round", join="round", fillrule=nothing, class="")
    isempty(pb.segs) && return
    segs = pb.segs
    pb.segs = Seg[]
    st = tocolor(stroke)
    _push!(c, PathPrim(segs, tocolor(fill), st, Float64(linewidth), dash, String(cap), String(join),
                       fillrule === nothing ? nothing : String(fillrule), String(class)))
    lw = isvisible(st) ? linewidth / 2 : 0.0
    b = pb.bbox
    grow!(c.bbox, b.xmin - lw, b.ymin - lw)
    grow!(c.bbox, b.xmax + lw, b.ymax + lw)
end

function line!(c::Canvas, x1, y1, x2, y2; color=:black, linewidth=1.0, dash=nothing, cap="round")
    pb = PathBuilder()
    M!(pb, x1, y1); L!(pb, x2, y2)
    path!(c, pb; stroke=color, linewidth, dash, cap)
end

function rect!(c::Canvas, x, y, w, h; fill=TRANSPARENT, stroke=TRANSPARENT, linewidth=1.0, rx=0.0,
               class="", gradient=RGBA[])
    _push!(c, RectPrim(x, y, w, h, tocolor(fill), tocolor(stroke), linewidth, rx, String(class),
                       collect(RGBA, gradient)))
    grow!(c.bbox, x, y); grow!(c.bbox, x + w, y + h)
end

function circle!(c::Canvas, x, y, r; fill=:black, stroke=TRANSPARENT, linewidth=1.0)
    _push!(c, CirclePrim(x, y, r, tocolor(fill), tocolor(stroke), linewidth))
    grow!(c.bbox, x - r, y - r); grow!(c.bbox, x + r, y + r)
end

# --- markers -------------------------------------------------------------------------

const MARKERS = (:circle, :square, :diamond, :utriangle, :dtriangle, :triangle, :star, :cross, :xcross,
                 :hexagon, :pentagon)

function _poly(c::Canvas, pts; fill, stroke, linewidth)
    pb = PathBuilder()
    for (k, (x, y)) in enumerate(pts)
        k == 1 ? M!(pb, x, y) : L!(pb, x, y)
    end
    Z!(pb)
    path!(c, pb; fill, stroke, linewidth)
end

_ngon(x, y, r, n, rot=-π / 2) = [(x + r * cos(rot + 2π * k / n), y + r * sin(rot + 2π * k / n)) for k in 0:n-1]

"""Draw marker `shape` of diameter `size` centred at (x, y)."""
function marker!(c::Canvas, x, y, shape::Symbol, size; fill=:black, stroke=TRANSPARENT, linewidth=1.0)
    r = size / 2
    if shape === :circle
        circle!(c, x, y, r; fill, stroke, linewidth)
    elseif shape === :square
        s = size * 0.886
        rect!(c, x - s / 2, y - s / 2, s, s; fill, stroke, linewidth)
    elseif shape === :diamond
        s = r * 1.25
        _poly(c, [(x, y - s), (x + s * 0.8, y), (x, y + s), (x - s * 0.8, y)]; fill, stroke, linewidth)
    elseif shape === :utriangle || shape === :triangle
        _poly(c, _ngon(x, y + r * 0.2, r * 1.25, 3); fill, stroke, linewidth)
    elseif shape === :dtriangle
        _poly(c, _ngon(x, y - r * 0.2, r * 1.25, 3, π / 2); fill, stroke, linewidth)
    elseif shape === :hexagon
        _poly(c, _ngon(x, y, r * 1.05, 6, 0.0); fill, stroke, linewidth)
    elseif shape === :pentagon
        _poly(c, _ngon(x, y, r * 1.1, 5); fill, stroke, linewidth)
    elseif shape === :star
        pts = Tuple{Float64,Float64}[]
        for k in 0:9
            rr = iseven(k) ? r * 1.3 : r * 0.55
            a = -π / 2 + π * k / 5
            push!(pts, (x + rr * cos(a), y + rr * sin(a)))
        end
        _poly(c, pts; fill, stroke, linewidth)
    elseif shape === :cross || shape === :xcross
        w = size * 0.32
        pts = [(-w, -r), (w, -r), (w, -w), (r, -w), (r, w), (w, w), (w, r), (-w, r), (-w, w), (-r, w), (-r, -w), (-w, -w)]
        a = shape === :xcross ? π / 4 : 0.0
        _poly(c, [(x + px * cos(a) - py * sin(a), y + px * sin(a) + py * cos(a)) for (px, py) in pts];
              fill, stroke, linewidth)
    else
        throw(ArgumentError("unknown marker :$shape; choose from $(MARKERS)"))
    end
end

"""Pie chart of `values` (any non-negative numbers) centred at (x, y)."""
function pie!(c::Canvas, x, y, r, values, colors; stroke=:white, linewidth=0.75, start=-π / 2)
    tot = sum(values)
    tot > 0 || return
    nz = count(>(0), values)
    if nz == 1
        k = findfirst(>(0), values)
        circle!(c, x, y, r; fill=colors[k], stroke, linewidth)
        return
    end
    a = start
    for (v, col) in zip(values, colors)
        v > 0 || continue
        Δ = 2π * v / tot
        pb = PathBuilder()
        M!(pb, x, y)
        L!(pb, x + r * cos(a), y + r * sin(a))
        arc!(pb, x, y, r, a, a + Δ)
        Z!(pb)
        path!(c, pb; fill=col, stroke, linewidth)
        a += Δ
    end
end

# --- text ------------------------------------------------------------------------------

"""
Draw text with its anchor at (x, y), rotated by `angle` degrees (clockwise).
`halign` is `:left`, `:center` or `:right`; `valign` is `:center`, `:baseline`,
`:top` or `:bottom`.
"""
function text!(c::Canvas, x, y, s::AbstractString; fontsize=10.0, angle=0.0, halign=:left, valign=:center,
               color=:black, bold=false, italic=false, family=nothing, halo=nothing, halowidth=3.0,
               class="")
    isempty(s) && return
    _push!(c, TextPrim(x, y, String(s), fontsize, angle, halign, valign, tocolor(color), bold, italic,
                       family === nothing ? nothing : String(family), tocolor(halo), halowidth, String(class)))
    # bounding box of the rotated text box
    w = textwidth_px(s, fontsize; bold)
    x0 = halign === :left ? 0.0 : halign === :center ? -w / 2 : -w
    h = fontsize
    yc = valign === :center ? 0.0 : valign === :top ? h / 2 : valign === :bottom ? -h / 2 : -0.3h
    a = deg2rad(angle)
    ca, sa = cos(a), sin(a)
    for (px, py) in ((x0, yc - h / 2), (x0 + w, yc - h / 2), (x0, yc + h / 2), (x0 + w, yc + h / 2))
        grow!(c.bbox, x + px * ca - py * sa, y + px * sa + py * ca)
    end
end

# --- images ----------------------------------------------------------------------------

"""An image (URL or data URI) fitted in the box (x, y, w, h), aspect ratio kept."""
function image!(c::Canvas, x, y, w, h, href::AbstractString; opacity=1.0)
    _push!(c, ImagePrim(x, y, w, h, String(href), false, opacity))
    grow!(c.bbox, x, y); grow!(c.bbox, x + w, y + h)
end

"""SVG markup fitted in the box (x, y, w, h)."""
function svgimage!(c::Canvas, x, y, w, h, svg::AbstractString)
    occursin(r"<svg\b"s, svg) || throw(ArgumentError("no <svg> element in image markup"))
    _push!(c, ImagePrim(x, y, w, h, String(svg), true, 1.0))
    grow!(c.bbox, x, y); grow!(c.bbox, x + w, y + h)
end

# --- the drawn figure -----------------------------------------------------------------

"""
    Scene

A fully laid-out figure: the recorded primitives, the area they cover (with
the margin added), the background colour and the default font. Every backend
draws from a `Scene`.
"""
struct Scene
    prims::Vector{Prim}
    x0::Float64
    y0::Float64
    width::Float64
    height::Float64
    background::RGBA
    font::String
end

# flattened arc: points from a1 to a2 (excluding the start), roughly every 4° and ≤ 3 px apart
function _arcpoints(s::Seg)
    Δ = s.a2 - s.a1
    n = clamp(ceil(Int, max(abs(Δ) / deg2rad(4), abs(Δ) * s.r / 3)), 1, 720)
    return [(s.cx + s.r * cos(s.a1 + Δ * k / n), s.cy + s.r * sin(s.a1 + Δ * k / n)) for k in 1:n]
end

"""
Polyline subpaths of a path, arcs flattened; each is a vector of points and a
flag saying whether it is closed.
"""
function _polylines(segs::Vector{Seg})
    out = Tuple{Vector{Tuple{Float64,Float64}},Bool}[]
    cur = Tuple{Float64,Float64}[]
    flush!(closed) = (length(cur) > 1 && push!(out, (cur, closed)); cur = Tuple{Float64,Float64}[])
    for s in segs
        if s.op == 'M'
            flush!(false)
            push!(cur, (s.x, s.y))
        elseif s.op == 'L'
            isempty(cur) && push!(cur, (s.x, s.y))
            push!(cur, (s.x, s.y))
        elseif s.op == 'A'
            append!(cur, _arcpoints(s))
        elseif s.op == 'Z'
            start = isempty(cur) ? (s.x, s.y) : cur[1]
            flush!(true)
            push!(cur, start)       # the pen returns to the subpath start
        end
    end
    flush!(false)
    return out
end

# cubic Bézier pieces (≤ 90° each) approximating an arc: (c1, c2, end) triples
function _arcbeziers(s::Seg)
    Δ = s.a2 - s.a1
    n = max(1, ceil(Int, abs(Δ) / (π / 2) - 1e-9))
    δ = Δ / n
    k = 4 / 3 * tan(δ / 4)
    out = NTuple{3,Tuple{Float64,Float64}}[]
    for i in 0:n-1
        a = s.a1 + δ * i; b = a + δ
        p0 = (s.cx + s.r * cos(a), s.cy + s.r * sin(a))
        p3 = (s.cx + s.r * cos(b), s.cy + s.r * sin(b))
        c1 = (p0[1] - k * s.r * sin(a), p0[2] + k * s.r * cos(a))
        c2 = (p3[1] + k * s.r * sin(b), p3[2] - k * s.r * cos(b))
        push!(out, (c1, c2, p3))
    end
    return out
end
