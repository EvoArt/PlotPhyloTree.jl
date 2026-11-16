# A minimal SVG canvas that tracks the bounding box of what is drawn.

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

mutable struct Canvas
    io::IOBuffer
    defs::IOBuffer
    bbox::BBox
    ids::Int
end
Canvas() = Canvas(IOBuffer(), IOBuffer(), BBox(), 0)

newid!(c::Canvas, prefix="p") = (c.ids += 1; string(prefix, c.ids))

# --- number and attribute formatting -------------------------------------------

function _num(io::IO, x::Real)
    x = Float64(x)
    isfinite(x) || (x = 0.0)
    r = round(x; digits=2)
    if r == round(r)
        print(io, Int(round(r)))
    else
        s = string(r)
        print(io, s)
    end
end
_num(x::Real) = sprint(_num, x)

function _esc(io::IO, s::AbstractString)
    for ch in s
        ch == '&' ? print(io, "&amp;") : ch == '<' ? print(io, "&lt;") :
        ch == '>' ? print(io, "&gt;") : ch == '"' ? print(io, "&quot;") : print(io, ch)
    end
end
_esc(s::AbstractString) = sprint(_esc, s)

_attr(io::IO, name, x::Real) = (print(io, ' ', name, "=\""); _num(io, x); print(io, '"'))
_attr(io::IO, name, s::AbstractString) = (print(io, ' ', name, "=\""); _esc(io, s); print(io, '"'))

_fill(io::IO, paint::AbstractString) = startswith(paint, "url(") ? _attr(io, "fill", paint) : _fill(io, tocolor(paint))
_fill(io::IO, c) = _fill(io, tocolor(c))
function _fill(io::IO, c::RGBA)
    if !isvisible(c)
        print(io, " fill=\"none\"")
    else
        print(io, " fill=\"", hexcolor(c), '"')
        c.a < 1 && _attr(io, "fill-opacity", round(c.a; digits=3))
    end
end

function _stroke(io::IO, c::RGBA, lw::Real; dash=nothing, cap="round", join="round")
    (isvisible(c) && lw > 0) || return
    print(io, " stroke=\"", hexcolor(c), '"')
    c.a < 1 && _attr(io, "stroke-opacity", round(c.a; digits=3))
    _attr(io, "stroke-width", lw)
    cap == "butt" || print(io, " stroke-linecap=\"", cap, '"')
    join == "miter" || print(io, " stroke-linejoin=\"", join, '"')
    if dash !== nothing
        d = _dasharray(dash, lw)
        isempty(d) || print(io, " stroke-dasharray=\"", d, '"')
    end
end

function _dasharray(dash, lw)
    dash === :solid && return ""
    dash === :dash && return string(_num(4lw + 2), ' ', _num(2lw + 2))
    dash === :dot && return string(_num(0.01), ' ', _num(2lw + 1.5))
    dash === :dashdot && return string(_num(4lw + 2), ' ', _num(2lw + 1), ' ', _num(0.01), ' ', _num(2lw + 1))
    dash isa AbstractString && return dash
    dash isa AbstractVector && return join(_num.(dash), ' ')
    throw(ArgumentError("linestyle must be :solid, :dash, :dot, :dashdot or a dash vector"))
end

# --- groups ------------------------------------------------------------------------

function group(f, c::Canvas, class::AbstractString=""; attrs::AbstractString="")
    print(c.io, "<g")
    isempty(class) || _attr(c.io, "class", class)
    isempty(attrs) || print(c.io, ' ', attrs)
    print(c.io, ">\n")
    f()
    print(c.io, "</g>\n")
end

# --- paths -------------------------------------------------------------------------

"""Incrementally built SVG path with bounding-box tracking."""
mutable struct PathBuilder
    d::IOBuffer
    bbox::BBox
    x::Float64
    y::Float64
end
PathBuilder() = PathBuilder(IOBuffer(), BBox(), 0.0, 0.0)

function M!(pb::PathBuilder, x, y)
    print(pb.d, 'M'); _num(pb.d, x); print(pb.d, ','); _num(pb.d, y)
    pb.x = x; pb.y = y
    grow!(pb.bbox, x, y)
    return pb
end
function L!(pb::PathBuilder, x, y)
    print(pb.d, 'L'); _num(pb.d, x); print(pb.d, ','); _num(pb.d, y)
    pb.x = x; pb.y = y
    grow!(pb.bbox, x, y)
    return pb
end
Z!(pb::PathBuilder) = (print(pb.d, 'Z'); pb)

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
    print(pb.d, 'A'); _num(pb.d, r); print(pb.d, ','); _num(pb.d, r)
    print(pb.d, " 0 ", abs(Δ) > π ? 1 : 0, ',', Δ > 0 ? 1 : 0, ' ')
    _num(pb.d, x2); print(pb.d, ','); _num(pb.d, y2)
    # bounding box: sample the arc
    n = max(2, ceil(Int, abs(Δ) / (π / 18)))
    for k in 0:n
        a = a1 + Δ * k / n
        grow!(pb.bbox, cx + r * cos(a), cy + r * sin(a))
    end
    pb.x = x2; pb.y = y2
    return pb
end

pathstring(pb::PathBuilder) = String(take!(copy(pb.d)))

function path!(c::Canvas, pb::PathBuilder; fill=TRANSPARENT, stroke=TRANSPARENT, linewidth=1.0,
               dash=nothing, cap="round", join="round", fillrule=nothing, class="", extra="")
    d = String(take!(pb.d))
    isempty(d) && return
    print(c.io, "<path d=\"", d, '"')
    isempty(class) || _attr(c.io, "class", class)
    _fill(c.io, tocolor(fill))
    _stroke(c.io, tocolor(stroke), linewidth; dash, cap, join)
    fillrule === nothing || print(c.io, " fill-rule=\"", fillrule, '"')
    isempty(extra) || print(c.io, ' ', extra)
    print(c.io, "/>\n")
    lw = isvisible(tocolor(stroke)) ? linewidth / 2 : 0.0
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
               class="", extra="")
    print(c.io, "<rect")
    _attr(c.io, "x", x); _attr(c.io, "y", y); _attr(c.io, "width", w); _attr(c.io, "height", h)
    rx > 0 && _attr(c.io, "rx", rx)
    isempty(class) || _attr(c.io, "class", class)
    _fill(c.io, fill)
    _stroke(c.io, tocolor(stroke), linewidth; join="miter")
    isempty(extra) || print(c.io, ' ', extra)
    print(c.io, "/>\n")
    grow!(c.bbox, x, y); grow!(c.bbox, x + w, y + h)
end

function circle!(c::Canvas, x, y, r; fill=:black, stroke=TRANSPARENT, linewidth=1.0, extra="")
    print(c.io, "<circle")
    _attr(c.io, "cx", x); _attr(c.io, "cy", y); _attr(c.io, "r", r)
    _fill(c.io, tocolor(fill))
    _stroke(c.io, tocolor(stroke), linewidth)
    isempty(extra) || print(c.io, ' ', extra)
    print(c.io, "/>\n")
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
               class="", extra="")
    isempty(s) && return
    col = tocolor(color)
    print(c.io, "<text")
    if angle == 0
        _attr(c.io, "x", x); _attr(c.io, "y", y)
    else
        print(c.io, " transform=\"translate("); _num(c.io, x); print(c.io, ','); _num(c.io, y)
        print(c.io, ") rotate("); _num(c.io, angle); print(c.io, ")\"")
    end
    dy = valign === :center ? 0.35 : valign === :top ? 0.75 : valign === :bottom ? -0.22 : 0.0
    dy != 0 && print(c.io, " dy=\"", dy, "em\"")
    _attr(c.io, "font-size", fontsize)
    halign === :left || print(c.io, " text-anchor=\"", halign === :center ? "middle" : "end", '"')
    bold && print(c.io, " font-weight=\"bold\"")
    italic && print(c.io, " font-style=\"italic\"")
    family === nothing || _attr(c.io, "font-family", String(family))
    isempty(class) || _attr(c.io, "class", class)
    _fill(c.io, col)
    if halo !== nothing && isvisible(tocolor(halo))
        print(c.io, " stroke=\"", hexcolor(tocolor(halo)), "\" stroke-width=\"", _num(halowidth),
              "\" stroke-linejoin=\"round\" paint-order=\"stroke\"")
    end
    isempty(extra) || print(c.io, ' ', extra)
    print(c.io, '>')
    _esc(c.io, s)
    print(c.io, "</text>\n")
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

function image!(c::Canvas, x, y, w, h, href::AbstractString; opacity=1.0)
    print(c.io, "<image")
    _attr(c.io, "x", x); _attr(c.io, "y", y); _attr(c.io, "width", w); _attr(c.io, "height", h)
    print(c.io, " preserveAspectRatio=\"xMidYMid meet\"")
    opacity < 1 && _attr(c.io, "opacity", opacity)
    print(c.io, " xlink:href=\"", href, "\"/>\n")
    grow!(c.bbox, x, y); grow!(c.bbox, x + w, y + h)
end

# SVG markup placed in the box (x, y, w, h) as a nested <svg> element
function svgimage!(c::Canvas, x, y, w, h, svg::AbstractString)
    m = match(r"<svg\b([^>]*?)(/?)>"s, svg)
    m === nothing && throw(ArgumentError("no <svg> element in image markup"))
    attrs = m.captures[1]
    vb = match(r"\bviewBox\s*=\s*[\"']([^\"']*)[\"']"i, attrs)
    if vb === nothing
        mw = match(r"\swidth\s*=\s*[\"']\s*([\d.]+)"i, attrs)
        mh = match(r"\sheight\s*=\s*[\"']\s*([\d.]+)"i, attrs)
        (mw !== nothing && mh !== nothing) && (attrs *= " viewBox=\"0 0 $(mw.captures[1]) $(mh.captures[1])\"")
    end
    attrs = replace(attrs, r"\s(x|y|width|height|preserveAspectRatio)\s*=\s*(\"[^\"]*\"|'[^']*')" => "")
    occursin("xmlns=", attrs) || (attrs *= " xmlns=\"http://www.w3.org/2000/svg\"")
    print(c.io, "<svg")
    _attr(c.io, "x", x); _attr(c.io, "y", y); _attr(c.io, "width", w); _attr(c.io, "height", h)
    print(c.io, " preserveAspectRatio=\"xMidYMid meet\"", attrs, m.captures[2], ">")
    print(c.io, svg[m.offset+ncodeunits(m.match):end])
    println(c.io)
    grow!(c.bbox, x, y); grow!(c.bbox, x + w, y + h)
end
