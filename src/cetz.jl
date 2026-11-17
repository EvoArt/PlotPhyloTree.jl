# CeTZ backend: writes a `Scene` as a Typst `cetz.canvas` (or a standalone
# Typst document). One px of the layout is one pt; y is flipped (CeTZ y points
# up); arcs become cubic Béziers. Only drawing functions shared by CeTZ 0.3 to
# 0.5 are used.

mutable struct CeTZWriter
    io::IOBuffer
    s::Float64
    imagedir::Union{Nothing,String}
    imageprefix::String
    nimages::Int
    measure::Bool                      # curved text measured by Typst (else the layout's glyphs)
end

_cz(w::CeTZWriter, x, y) = string('(', _num(w.s * x), ", ", _num(-w.s * y), ')')
_cpt(w::CeTZWriter, x::Real) = string(_num(w.s * x), "pt")

function _typcolor(c::RGBA)
    h = hexcolor(c)
    c.a < 1 && (h *= string(_byte(c.a); base=16, pad=2))
    return string("rgb(\"", h, "\")")
end

_typstr(s::AbstractString) = string('"', replace(s, '\\' => "\\\\", '"' => "\\\""), '"')

function _cetzstyle(w::CeTZWriter, fill::RGBA, stroke::RGBA, lw; dash=nothing, cap="round", join="round")
    f = isvisible(fill) ? _typcolor(fill) : "none"
    st = "none"
    if isvisible(stroke) && lw > 0
        parts = ["paint: " * _typcolor(stroke), "thickness: " * _cpt(w, lw), "cap: \"$cap\"", "join: \"$join\""]
        d = _dashvec(dash, lw)
        isempty(d) || push!(parts, "dash: (" * Base.join((_cpt(w, v) for v in d), ", ") * ",)")
        st = "(" * Base.join(parts, ", ") * ")"
    end
    return f, st
end

function _cetz!(w::CeTZWriter, g::GroupPrim)
    isempty(g.class) || print(w.io, "  // ", g.class, "\n")
    for p in g.children
        _cetz!(w, p)
    end
end

# subpaths of a path as (segments, closed)
function _subpaths(segs::Vector{Seg})
    out = Tuple{Vector{Seg},Bool}[]
    cur = Seg[]
    for s in segs
        if s.op == 'M'
            length(cur) > 1 && push!(out, (cur, false))
            cur = [s]
        elseif s.op == 'Z'
            length(cur) > 1 && push!(out, (cur, true))
            cur = isempty(cur) ? Seg[] : [Seg('M', cur[1].x, cur[1].y)]
        else
            isempty(cur) && push!(cur, Seg('M', s.x, s.y))
            push!(cur, s)
        end
    end
    length(cur) > 1 && push!(out, (cur, false))
    return out
end

function _cetz!(w::CeTZWriter, p::PathPrim)
    fill, stroke = _cetzstyle(w, p.fill, p.stroke, p.linewidth; p.dash, p.cap, p.join)
    fill == "none" && stroke == "none" && return
    io = w.io
    style = "fill: $fill, stroke: $stroke"
    for (segs, closed) in _subpaths(p.segs)
        if all(s -> s.op != 'A', segs)
            print(io, "  line(")
            for s in segs
                print(io, _cz(w, s.x, s.y), ", ")
            end
            print(io, closed ? "close: true, " : "", style, ")\n")
        else
            print(io, "  merge-path(", closed ? "close: true, " : "", style, ", {\n")
            x, y = segs[1].x, segs[1].y
            for s in segs[2:end]
                if s.op == 'L'
                    print(io, "    line(", _cz(w, x, y), ", ", _cz(w, s.x, s.y), ")\n")
                else
                    for (c1, c2, e) in _arcbeziers(s)
                        print(io, "    bezier(", _cz(w, x, y), ", ", _cz(w, e...), ", ", _cz(w, c1...), ", ",
                              _cz(w, c2...), ")\n")
                        x, y = e
                    end
                end
                x, y = s.x, s.y
            end
            print(io, "  })\n")
        end
    end
end

function _cetz!(w::CeTZWriter, p::RectPrim)
    a = _cz(w, p.x, p.y); b = _cz(w, p.x + p.w, p.y + p.h)
    if !isempty(p.gradient)
        g = length(p.gradient) == 1 ? _typcolor(p.gradient[1]) :
            "gradient.linear(" * Base.join(_typcolor.(p.gradient), ", ") * ")"
        print(w.io, "  rect(", a, ", ", b, ", fill: ", g, ", stroke: none)\n")
        return
    end
    fill, stroke = _cetzstyle(w, p.fill, p.stroke, p.linewidth; join="miter")
    fill == "none" && stroke == "none" && return
    print(w.io, "  rect(", a, ", ", b, ", fill: ", fill, ", stroke: ", stroke,
          p.rx > 0 ? ", radius: " * _num(w.s * p.rx) : "", ")\n")
end

function _cetz!(w::CeTZWriter, p::CirclePrim)
    fill, stroke = _cetzstyle(w, p.fill, p.stroke, p.linewidth)
    fill == "none" && stroke == "none" && return
    print(w.io, "  circle(", _cz(w, p.x, p.y), ", radius: ", _num(w.s * p.r), ", fill: ", fill, ", stroke: ", stroke, ")\n")
end

# text is anchored on its baseline at the point the SVG puts it (see _baseline);
# CeTZ's "mid" anchors depend on each string's ink and vary between versions
_cetzanchor(h::Symbol) = h === :center ? "base" : h === :left ? "base-west" : "base-east"

# Fixed box edges (cap height to baseline) make every string's box bottom its
# baseline, so CeTZ's "base" anchors land on the baseline whatever the glyphs
# (CeTZ otherwise measures each string's own ink, differently by version).
function _textargs(w::CeTZWriter, fontsize, bold, italic, family=nothing)
    targs = "size: " * _cpt(w, fontsize) * ", top-edge: \"cap-height\", bottom-edge: \"baseline\""
    bold && (targs *= ", weight: \"bold\"")
    italic && (targs *= ", style: \"italic\"")
    if family !== nothing
        fl = _fontlist(family)
        isempty(fl) || (targs *= ", font: (" * Base.join(_typstr.(fl), ", ") * ",)")
    end
    return targs
end

function _cetz!(w::CeTZWriter, p::TextPrim)
    targs = _textargs(w, p.fontsize, p.bold, p.italic, p.family)
    s = _typstr(p.text)
    pos = _cz(w, _baseline(p)...)
    tail = ", anchor: \"" * _cetzanchor(p.halign) * "\", padding: 0" *
           (p.angle == 0 ? "" : ", angle: " * _num(-p.angle) * "deg") * ")\n"
    if isvisible(p.halo) && p.halowidth > 0
        print(w.io, "  content(", pos, ", text(", targs, ", fill: ", _typcolor(p.halo), ", stroke: (paint: ",
              _typcolor(p.halo), ", thickness: ", _cpt(w, p.halowidth), ", join: \"round\"), ", s, ")", tail)
    end
    print(w.io, "  content(", pos, ", text(", targs, ", fill: ", _typcolor(p.color), ", ", s, ")", tail)
end

# Curved text: Typst measures each character in the document's font and the
# letters are laid along the arc from those widths (the canvas runs in a
# `context`, so `measure` sees the document's text settings).
function _cetz!(w::CeTZWriter, p::ArcTextPrim)
    if !w.measure
        foreach(g -> _cetz!(w, g), p.glyphs)
        return
    end
    s = w.s
    rb = s * (p.r - (p.clockwise ? 1 : -1) * 0.35 * p.fontsize)     # baseline radius
    dir = p.clockwise ? -1 : 1                                        # Typst angles run anticlockwise
    rot = p.clockwise ? "-90deg" : "90deg"
    st = _textargs(w, p.fontsize, p.bold, p.italic) * ", fill: " * _typcolor(p.color)
    io = w.io
    print(io, "  {\n    let st = (", st, ")\n",
          "    let cs = ", _typstr(p.text), ".clusters()\n",
          "    let sp = (measure(text(..st, \"x x\")).width - measure(text(..st, \"xx\")).width) / 1pt\n",
          "    let ws = cs.map(c => if c == \" \" { sp } else { measure(text(..st, c)).width / 1pt })\n",
          "    let (cx, cy, rb, dir) = (", _num(s * p.cx), ", ", _num(-s * p.cy), ", ", _num(rb), ", ", dir, ")\n",
          "    let a = ", _num(-rad2deg(p.φ)), "deg - dir * ws.sum() / (2 * rb) * 1rad\n",
          "    for (c, cw) in cs.zip(ws) {\n",
          "      let m = a + dir * cw / (2 * rb) * 1rad\n",
          "      if c != \" \" { content((cx + rb * calc.cos(m), cy + rb * calc.sin(m)), text(..st, c), ",
          "anchor: \"base\", padding: 0, angle: m + ", rot, ") }\n",
          "      a += dir * cw / rb * 1rad\n    }\n  }\n")
end

function _cetz!(w::CeTZWriter, p::ImagePrim)
    w.nimages += 1
    name = _exportimage(p, w.imagedir, w.imageprefix, w.nimages, (".png", ".jpg", ".gif", ".svg"))
    name === nothing && return
    print(w.io, "  content(", _cz(w, p.x + p.w / 2, p.y + p.h / 2), ", image(", _typstr(name), ", width: ",
          _cpt(w, p.w), ", height: ", _cpt(w, p.h), ", fit: \"contain\"), padding: 0)\n")
end

const CETZ_VERSION = "0.4.2"

# fonts for a standalone document, matching the layout metrics
function _typstfonts(m::FontMetrics)
    n = m.name
    n == "Helvetica" && return ["Helvetica", "Arial", "TeX Gyre Heros", "Liberation Sans"]
    n == "Latin Modern Roman" && return ["Latin Modern Roman", "New Computer Modern"]
    n == "Latin Modern Sans" && return ["Latin Modern Sans", "New Computer Modern Sans"]
    n == "Times" && return ["Times New Roman", "TeX Gyre Termes", "Liberation Serif"]
    return [n]
end

"""
    cetzstring(p; standalone=false, scale=1, cetz="$CETZ_VERSION", font=nothing,
               curvedtext=:native) -> String

The figure as Typst code drawing it with [CeTZ](https://typst.app/universe/package/cetz).
The code imports `@preview/cetz:<cetz>` and draws a `cetz.canvas`; `#include`
the saved file in a Typst document, or with `standalone = true` it sets the
page to fit the figure so it compiles on its own (`typst compile tree.typ`).

Geometry is fixed by the layout (1 px = 1 pt; `scale` multiplies every
length, font sizes included). Text is handed to Typst: labels use the
**document's font** — whatever `#set text(font: …)` is in force where the
file is included — at the layout's sizes. `font` (a name or list) sets a
font for this figure instead; a standalone document picks one matching the
layout metrics. Lay the tree out with the metrics of the document font
(`treeplot(…; metrics=…)`, see [`fontmetrics`](@ref)) so label bands and the
legend fit. Curved clade labels are spaced by Typst, which measures each
letter in the document font (`curvedtext = :glyphs` places the letters as the
layout did instead).

Pick `cetz` to match your Typst version (CeTZ 0.3.0 needs Typst ≥ 0.11, 0.4
needs 0.13.1, 0.5 needs 0.14).

Images are written beside the file by [`savefig`](@ref) (`"tree.typ"` →
`tree-img-1.png` …); Typst draws SVG images itself.
"""
cetzstring(p::TreePlot; kwargs...) = cetzdocument(scene(p); kwargs...)

function cetzdocument(sc::Scene; standalone::Bool=false, scale::Real=1, cetz::AbstractString=CETZ_VERSION,
                      font=nothing, curvedtext::Symbol=:native, imagedir=nothing,
                      imageprefix::AbstractString="img")
    curvedtext in (:native, :glyphs) || throw(ArgumentError("curvedtext must be :native or :glyphs"))
    w = CeTZWriter(IOBuffer(), Float64(scale), imagedir === nothing ? nothing : String(imagedir),
                   String(imageprefix), 0, curvedtext === :native)
    for p in sc.prims
        _cetz!(w, p)
    end
    fonts = font !== nothing ? (font isa AbstractString ? [String(font)] : String.(collect(font))) :
            standalone ? _typstfonts(sc.metrics) : String[]
    io = IOBuffer()
    print(io, "// PlotPhyloTree figure: ", _num(w.s * sc.width), " x ", _num(w.s * sc.height), " pt\n")
    print(io, "#import \"@preview/cetz:", cetz, "\"\n")
    bg = sc.background
    standalone && print(io, "#set page(width: auto, height: auto, margin: 0pt",
                        isvisible(bg) ? ", fill: " * _typcolor(bg) : "", ")\n")
    print(io, "#[\n")
    isempty(fonts) || print(io, "#set text(font: (", Base.join(_typstr.(fonts), ", "), ",), fallback: true)\n")
    print(io, "#context cetz.canvas(length: 1pt, {\n  import cetz.draw: *\n")
    # fix the canvas to the figure's area (and paint the background)
    print(io, "  rect(", _cz(w, sc.x0, sc.y0), ", ", _cz(w, sc.x0 + sc.width, sc.y0 + sc.height), ", stroke: none, fill: ",
          isvisible(bg) ? _typcolor(bg) : "none", ")\n")
    print(io, String(take!(w.io)))
    print(io, "})\n]\n")
    return String(take!(io))
end
