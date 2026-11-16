# Label collision avoidance.
#
# Layers draw movable labels with `softtext!`, giving candidate placements in
# order of preference. After every layer is drawn, `resolve_labels!` indexes
# what is on the canvas (strokes, filled shapes, text, markers, images — but not
# background fills such as clade wedges and time bands) and replaces each soft
# label by its first candidate that overlaps nothing, or drops it. Backends
# never see soft labels.

"""A text label with alternative placements, resolved after drawing."""
struct SoftTextPrim <: Prim
    candidates::Vector{TextPrim}
    required::Bool       # if no candidate fits: draw the first (true) or drop it (false)
    priority::Float64    # higher is placed first
end

# primitives with these classes never block a label (backgrounds and guides)
const PASSIVE_CLASSES = ("highlight", "background", "grid")

"""
    softtext!(c, candidates; required=false, priority=0)

Queue a label to be placed at the first of `candidates` (named tuples or
`TextPrim`s with the keyword arguments of [`text!`](@ref) plus `x`, `y`,
`text`) that collides with nothing once everything else is drawn.
"""
function softtext!(c::Canvas, candidates; required::Bool=false, priority::Real=0)
    tps = TextPrim[_textprim(k) for k in candidates]
    filter!(t -> !isempty(t.text), tps)
    isempty(tps) && return
    _push!(c, SoftTextPrim(tps, required, Float64(priority)))
end

_textprim(t::TextPrim) = t
function _textprim(k::NamedTuple)
    g(s, d) = haskey(k, s) ? k[s] : d
    TextPrim(Float64(k.x), Float64(k.y), String(k.text), Float64(g(:fontsize, 10.0)), Float64(g(:angle, 0.0)),
             g(:halign, :left), g(:valign, :center), tocolor(g(:color, :black)), g(:bold, false), g(:italic, false),
             g(:family, nothing), tocolor(g(:halo, nothing)), Float64(g(:halowidth, 3.0)), String(g(:class, "")))
end

# --- geometry ---------------------------------------------------------------------------

const Pt = Tuple{Float64,Float64}

# corners of the rotated box a text primitive covers, grown by `pad` px
function _textquad(t::TextPrim, pad::Real=0.0)
    w = textwidth_px(t.text, t.fontsize; bold=t.bold)
    h = t.fontsize
    x0 = t.halign === :left ? 0.0 : t.halign === :center ? -w / 2 : -w
    yc = t.valign === :center ? 0.0 : t.valign === :top ? h / 2 : t.valign === :bottom ? -h / 2 : -0.3h
    # glyphs fill about 0.75 em vertically; the box is the ink, not the line height
    hh = 0.38h + pad
    a = deg2rad(t.angle)
    ca, sa = cos(a), sin(a)
    return Pt[(t.x + px * ca - py * sa, t.y + px * sa + py * ca)
              for (px, py) in ((x0 - pad, yc - hh), (x0 + w + pad, yc - hh), (x0 + w + pad, yc + hh),
                               (x0 - pad, yc + hh))]
end

_rectpts(x, y, w, h) = Pt[(x, y), (x + w, y), (x + w, y + h), (x, y + h)]

function _bboxof(pts)
    xmin = ymin = Inf; xmax = ymax = -Inf
    for (x, y) in pts
        xmin = min(xmin, x); xmax = max(xmax, x); ymin = min(ymin, y); ymax = max(ymax, y)
    end
    return xmin, ymin, xmax, ymax
end

# separating-axis test for two convex polygons (a 2-point polygon is a segment)
function _convex_overlap(a::AbstractVector{Pt}, b::AbstractVector{Pt})
    for poly in (a, b)
        n = length(poly)
        for i in 1:(n == 2 ? 1 : n)
            p, q = poly[i], poly[mod1(i + 1, n)]
            ax, ay = -(q[2] - p[2]), q[1] - p[1]        # edge normal
            (ax == 0 && ay == 0) && continue
            amin = bmin = Inf; amax = bmax = -Inf
            for (x, y) in a
                d = x * ax + y * ay; amin = min(amin, d); amax = max(amax, d)
            end
            for (x, y) in b
                d = x * ax + y * ay; bmin = min(bmin, d); bmax = max(bmax, d)
            end
            (amax < bmin || bmax < amin) && return false
        end
    end
    return true
end

function _inside(pt::Pt, poly::AbstractVector{Pt})
    x, y = pt
    inside = false
    n = length(poly)
    j = n
    for i in 1:n
        xi, yi = poly[i]; xj, yj = poly[j]
        if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi
            inside = !inside
        end
        j = i
    end
    return inside
end

# --- the obstacle index ------------------------------------------------------------------

# an obstacle: a convex piece (segment, box, polygon) or the interior of a filled polygon
struct Obstacle
    pts::Vector{Pt}
    area::Bool           # a filled (possibly non-convex) polygon: blocks labels inside it
end

mutable struct Collider
    cell::Float64
    grid::Dict{Tuple{Int,Int},Vector{Int}}
    obs::Vector{Obstacle}
    stamp::Vector{Int}
    query::Int
end
Collider(cell=24.0) = Collider(cell, Dict{Tuple{Int,Int},Vector{Int}}(), Obstacle[], Int[], 0)

_cellrange(cl::Collider, lo, hi) = floor(Int, lo / cl.cell):floor(Int, hi / cl.cell)

function addobstacle!(cl::Collider, pts::Vector{Pt}; area::Bool=false)
    length(pts) < 2 && return cl
    push!(cl.obs, Obstacle(pts, area))
    push!(cl.stamp, 0)
    id = length(cl.obs)
    xmin, ymin, xmax, ymax = _bboxof(pts)
    (isfinite(xmin) && isfinite(ymin) && isfinite(xmax) && isfinite(ymax)) || return cl
    for i in _cellrange(cl, xmin, xmax), j in _cellrange(cl, ymin, ymax)
        push!(get!(Vector{Int}, cl.grid, (i, j)), id)
    end
    return cl
end

"""Does the convex polygon `q` touch any obstacle?"""
function collides(cl::Collider, q::Vector{Pt})
    cl.query += 1
    xmin, ymin, xmax, ymax = _bboxof(q)
    cx = sum(first, q) / length(q); cy = sum(last, q) / length(q)
    for i in _cellrange(cl, xmin, xmax), j in _cellrange(cl, ymin, ymax)
        ids = get(cl.grid, (i, j), nothing)
        ids === nothing && continue
        for id in ids
            cl.stamp[id] == cl.query && continue
            cl.stamp[id] = cl.query
            o = cl.obs[id]
            if o.area
                # edges crossing the label, or the label sitting inside the shape
                n = length(o.pts)
                for k in 1:n
                    _convex_overlap(q, Pt[o.pts[k], o.pts[mod1(k + 1, n)]]) && return true
                end
                _inside((cx, cy), o.pts) && return true
            else
                _convex_overlap(q, o.pts) && return true
            end
        end
    end
    return false
end

function _addprim!(cl::Collider, p::Prim) end

function _addprim!(cl::Collider, p::PathPrim)
    p.class in PASSIVE_CLASSES && return
    stroked = isvisible(p.stroke) && p.linewidth > 0
    filled = isvisible(p.fill)
    (stroked || filled) || return
    hw = stroked ? p.linewidth / 2 : 0.0
    for (pts, closed) in _polylines(p.segs)
        if filled && (closed || length(pts) > 2)
            addobstacle!(cl, pts; area=true)
        end
        if stroked
            for k in 1:length(pts)-1
                a, b = pts[k], pts[k+1]
                if hw > 0.75
                    # a thick stroke: the segment as a box
                    dx, dy = b[1] - a[1], b[2] - a[2]
                    L = hypot(dx, dy)
                    L < 1e-9 && continue
                    nx, ny = -dy / L * hw, dx / L * hw
                    addobstacle!(cl, Pt[(a[1] + nx, a[2] + ny), (b[1] + nx, b[2] + ny),
                                        (b[1] - nx, b[2] - ny), (a[1] - nx, a[2] - ny)])
                else
                    addobstacle!(cl, Pt[a, b])
                end
            end
        end
    end
end

function _addprim!(cl::Collider, p::RectPrim)
    p.class in PASSIVE_CLASSES && return
    (isvisible(p.fill) || isvisible(p.stroke) || !isempty(p.gradient)) || return
    addobstacle!(cl, _rectpts(p.x, p.y, p.w, p.h))
end

function _addprim!(cl::Collider, p::CirclePrim)
    (isvisible(p.fill) || isvisible(p.stroke)) || return
    r = p.r + (isvisible(p.stroke) ? p.linewidth / 2 : 0.0)
    addobstacle!(cl, Pt[(p.x + r * cos(a), p.y + r * sin(a)) for a in range(0, 2π; length=9)[1:8]])
end

_addprim!(cl::Collider, p::TextPrim) = p.class in PASSIVE_CLASSES || addobstacle!(cl, _textquad(p))
_addprim!(cl::Collider, p::ImagePrim) = addobstacle!(cl, _rectpts(p.x, p.y, p.w, p.h))

"""An index of everything drawn on `c` that a label must not cover."""
function collider(c::Canvas)
    cl = Collider()
    foreachprim(p -> _addprim!(cl, p), c.prims)
    return cl
end

# --- resolving soft labels -----------------------------------------------------------------

const LABEL_PAD = 1.5

"""
    resolve_labels!(c) -> c

Place every soft label on `c`: highest priority first (then drawing order), at
its first candidate that collides with nothing already drawn or placed.
"""
function resolve_labels!(c::Canvas)
    soft = Tuple{Vector{Prim},Int}[]
    _findsoft!(soft, c.prims)
    isempty(soft) && return c
    cl = collider(c)
    order = sortperm(soft; by=s -> -s[1][s[2]].priority)     # stable: drawing order within a priority
    for k in order
        v, i = soft[k]
        sp = v[i]::SoftTextPrim
        chosen = nothing
        for t in sp.candidates
            if !collides(cl, _textquad(t, LABEL_PAD))
                chosen = t
                break
            end
        end
        chosen === nothing && sp.required && (chosen = first(sp.candidates))
        if chosen === nothing
            v[i] = GroupPrim("", Prim[])          # dropped (an empty group draws nothing)
        else
            v[i] = chosen
            q = _textquad(chosen)
            addobstacle!(cl, q)
            for (x, y) in q
                grow!(c.bbox, x, y)
            end
        end
    end
    return c
end

function _findsoft!(out, prims::Vector{Prim})
    for (i, p) in enumerate(prims)
        if p isa SoftTextPrim
            push!(out, (prims, i))
        elseif p isa GroupPrim
            _findsoft!(out, p.children)
        end
    end
    return out
end

"""Is the box (x, y, w, h) free of everything drawn on `c`?"""
boxfree(c::Canvas, x, y, w, h) = !collides(collider(c), _rectpts(x, y, w, h))
