# SVG backend: writes a `Scene` as an SVG document.

# --- number and attribute formatting -------------------------------------------

function _num(io::IO, x::Real)
    x = Float64(x)
    isfinite(x) || (x = 0.0)
    r = round(x; digits=2)
    if r == round(r)
        print(io, Int(round(r)))
    else
        print(io, string(r))
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
        d = dash isa AbstractString ? dash : Base.join(_num.(_dashvec(dash, lw)), ' ')
        isempty(d) || print(io, " stroke-dasharray=\"", d, '"')
    end
end

# --- primitives ----------------------------------------------------------------------

mutable struct SVGWriter
    io::IOBuffer
    defs::IOBuffer
    ids::Int
end

function _svgpath(io::IO, segs::Vector{Seg})
    for s in segs
        if s.op == 'M' || s.op == 'L'
            print(io, s.op); _num(io, s.x); print(io, ','); _num(io, s.y)
        elseif s.op == 'A'
            Δ = s.a2 - s.a1
            print(io, 'A'); _num(io, s.r); print(io, ','); _num(io, s.r)
            print(io, " 0 ", abs(Δ) > π ? 1 : 0, ',', Δ > 0 ? 1 : 0, ' ')
            _num(io, s.x); print(io, ','); _num(io, s.y)
        else
            print(io, 'Z')
        end
    end
end

function _svg!(w::SVGWriter, g::GroupPrim)
    io = w.io
    print(io, "<g")
    isempty(g.class) || _attr(io, "class", g.class)
    print(io, ">\n")
    for p in g.children
        _svg!(w, p)
    end
    print(io, "</g>\n")
end

function _svg!(w::SVGWriter, p::PathPrim)
    io = w.io
    print(io, "<path d=\"")
    _svgpath(io, p.segs)
    print(io, '"')
    isempty(p.class) || _attr(io, "class", p.class)
    _fill(io, p.fill)
    _stroke(io, p.stroke, p.linewidth; p.dash, p.cap, p.join)
    p.fillrule === nothing || print(io, " fill-rule=\"", p.fillrule, '"')
    print(io, "/>\n")
end

function _svg!(w::SVGWriter, p::RectPrim)
    io = w.io
    gid = ""
    if !isempty(p.gradient)
        w.ids += 1
        gid = string("cb", w.ids)
        print(w.defs, "<linearGradient id=\"", gid, "\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\">")
        n = length(p.gradient)
        for (k, col) in enumerate(p.gradient)
            print(w.defs, "<stop offset=\"", round((k - 1) / max(n - 1, 1); digits=4), "\" stop-color=\"",
                  hexcolor(col), "\"/>")
        end
        print(w.defs, "</linearGradient>\n")
    end
    print(io, "<rect")
    _attr(io, "x", p.x); _attr(io, "y", p.y); _attr(io, "width", p.w); _attr(io, "height", p.h)
    p.rx > 0 && _attr(io, "rx", p.rx)
    isempty(p.class) || _attr(io, "class", p.class)
    isempty(gid) ? _fill(io, p.fill) : _attr(io, "fill", "url(#$gid)")
    _stroke(io, p.stroke, p.linewidth; join="miter")
    print(io, "/>\n")
end

function _svg!(w::SVGWriter, p::CirclePrim)
    io = w.io
    print(io, "<circle")
    _attr(io, "cx", p.x); _attr(io, "cy", p.y); _attr(io, "r", p.r)
    _fill(io, p.fill)
    _stroke(io, p.stroke, p.linewidth)
    print(io, "/>\n")
end

function _svg!(w::SVGWriter, p::TextPrim)
    io = w.io
    print(io, "<text")
    if p.angle == 0
        _attr(io, "x", p.x); _attr(io, "y", p.y)
    else
        print(io, " transform=\"translate("); _num(io, p.x); print(io, ','); _num(io, p.y)
        print(io, ") rotate("); _num(io, p.angle); print(io, ")\"")
    end
    va = p.valign
    dy = va === :center ? 0.35 : va === :top ? 0.75 : va === :bottom ? -0.22 : 0.0
    dy != 0 && print(io, " dy=\"", dy, "em\"")
    _attr(io, "font-size", p.fontsize)
    p.halign === :left || print(io, " text-anchor=\"", p.halign === :center ? "middle" : "end", '"')
    p.bold && print(io, " font-weight=\"bold\"")
    p.italic && print(io, " font-style=\"italic\"")
    p.family === nothing || _attr(io, "font-family", p.family)
    isempty(p.class) || _attr(io, "class", p.class)
    _fill(io, p.color)
    if isvisible(p.halo)
        print(io, " stroke=\"", hexcolor(p.halo), "\" stroke-width=\"", _num(p.halowidth),
              "\" stroke-linejoin=\"round\" paint-order=\"stroke\"")
    end
    print(io, '>')
    _esc(io, p.text)
    print(io, "</text>\n")
end

_svg!(w::SVGWriter, p::ArcTextPrim) = foreach(g -> _svg!(w, g), p.glyphs)

function _svg!(w::SVGWriter, p::ImagePrim)
    io = w.io
    if !p.svg
        print(io, "<image")
        _attr(io, "x", p.x); _attr(io, "y", p.y); _attr(io, "width", p.w); _attr(io, "height", p.h)
        print(io, " preserveAspectRatio=\"xMidYMid meet\"")
        p.opacity < 1 && _attr(io, "opacity", p.opacity)
        print(io, " xlink:href=\"", p.src, "\"/>\n")
        return
    end
    # SVG markup as a nested <svg> element (librsvg cannot draw SVG inside <image>)
    svg = p.src
    m = match(r"<svg\b([^>]*?)(/?)>"s, svg)
    attrs = m.captures[1]
    vb = match(r"\bviewBox\s*=\s*[\"']([^\"']*)[\"']"i, attrs)
    if vb === nothing
        mw = match(r"\swidth\s*=\s*[\"']\s*([\d.]+)"i, attrs)
        mh = match(r"\sheight\s*=\s*[\"']\s*([\d.]+)"i, attrs)
        (mw !== nothing && mh !== nothing) && (attrs *= " viewBox=\"0 0 $(mw.captures[1]) $(mh.captures[1])\"")
    end
    attrs = replace(attrs, r"\s(x|y|width|height|preserveAspectRatio)\s*=\s*(\"[^\"]*\"|'[^']*')" => "")
    occursin("xmlns=", attrs) || (attrs *= " xmlns=\"http://www.w3.org/2000/svg\"")
    print(io, "<svg")
    _attr(io, "x", p.x); _attr(io, "y", p.y); _attr(io, "width", p.w); _attr(io, "height", p.h)
    print(io, " preserveAspectRatio=\"xMidYMid meet\"", attrs, m.captures[2], ">")
    print(io, svg[m.offset+ncodeunits(m.match):end])
    println(io)
end

# --- document --------------------------------------------------------------------------

function svgdocument(s::Scene)
    w = SVGWriter(IOBuffer(), IOBuffer(), 0)
    for p in s.prims
        _svg!(w, p)
    end
    io = IOBuffer()
    print(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\"")
    _attr(io, "width", s.width); _attr(io, "height", s.height)
    print(io, " viewBox=\""); _num(io, s.x0); print(io, ' '); _num(io, s.y0); print(io, ' ')
    _num(io, s.width); print(io, ' '); _num(io, s.height); print(io, '"')
    _attr(io, "font-family", s.font)
    print(io, ">\n")
    defs = String(take!(w.defs))
    isempty(defs) || print(io, "<defs>\n", defs, "</defs>\n")
    if isvisible(s.background)
        print(io, "<rect")
        _attr(io, "x", s.x0); _attr(io, "y", s.y0); _attr(io, "width", s.width); _attr(io, "height", s.height)
        _fill(io, s.background)
        print(io, "/>\n")
    end
    print(io, String(take!(w.io)))
    print(io, "</svg>\n")
    return String(take!(io))
end
