# TikZ backend: writes a `Scene` as a `tikzpicture` (or a standalone LaTeX
# document). One px of the layout is one bp; y is flipped (TikZ y points up).
# Text is set in the document's font, so label widths differ a little from the
# SVG output; anchors keep every label in place.

# --- images shared by the TikZ and CeTZ backends ----------------------------------------

const _EXT = Dict("image/png" => ".png", "image/jpeg" => ".jpg", "image/gif" => ".gif", "image/webp" => ".webp",
                  "image/svg+xml" => ".svg")

"""
Write image `k` of a scene to `dir` as `<prefix>-<k>.<ext>` and return its
file name, or `nothing` (with a warning) if it cannot be written. `formats`
lists the extensions the target can include; SVG markup is converted to PDF
when `.svg` is not among them (needs the Librsvg extension).
"""
function _exportimage(img::ImagePrim, dir, prefix, k, formats)
    if dir === nothing
        @warn "images are only written when saving to a file (savefig); skipping image $k"
        return nothing
    end
    if img.svg
        if ".svg" in formats
            name = "$prefix-$k.svg"
            write(joinpath(dir, name), img.src)
            return name
        end
        name = "$prefix-$k.pdf"
        try
            _rasterize(joinpath(dir, name), img.src, ".pdf", 1.0)
            return name
        catch err
            @warn "SVG image $k needs converting to PDF for this backend (`using Librsvg_jll`); skipped" exception = err
            return nothing
        end
    end
    m = match(r"^data:([^;,]+)(;base64)?,(.*)$"s, img.src)
    if m === nothing
        @warn "image $k is a URL; download it and pass the file instead. Skipped" url = first(img.src, 80)
        return nothing
    end
    ext = get(_EXT, m.captures[1], nothing)
    if ext === nothing || !(ext in formats)
        @warn "image $k has type $(m.captures[1]), which this backend cannot include; skipped"
        return nothing
    end
    bytes = m.captures[2] === nothing ? Vector{UInt8}(codeunits(m.captures[3])) : base64decode(m.captures[3])
    name = "$prefix-$k$ext"
    write(joinpath(dir, name), bytes)
    return name
end

# font families named in a CSS font list (generic families dropped)
function _fontlist(font::AbstractString)
    fams = [strip(strip(f), ['"', '\'']) for f in split(font, ',')]
    return [String(f) for f in fams if !isempty(f) && !(lowercase(f) in ("sans-serif", "serif", "monospace", "cursive", "fantasy", "system-ui"))]
end


# --- TikZ -----------------------------------------------------------------------------

mutable struct TikZWriter
    io::IOBuffer
    s::Float64                         # scale
    colors::Dict{UInt32,String}
    colordefs::IOBuffer
    family::String                     # font code added to every label ("" = document font)
    curved::Symbol                     # :native (text along path) or :glyphs
    imagedir::Union{Nothing,String}
    imageprefix::String
    nimages::Int
end

_tk(w::TikZWriter, x::Real) = _num(w.s * x)
_pt(w::TikZWriter, x::Real) = string(_num(w.s * x), "bp")
_xy(w::TikZWriter, x, y) = string('(', _num(w.s * x), ',', _num(-w.s * y), ')')

function _tcolor(w::TikZWriter, c::RGBA)
    key = (UInt32(_byte(c.r)) << 16) | (UInt32(_byte(c.g)) << 8) | UInt32(_byte(c.b))
    get!(w.colors, key) do
        name = string("ppt", length(w.colors) + 1)
        print(w.colordefs, "\\definecolor{", name, "}{HTML}{", uppercase(string(key; base=16, pad=6)), "}\n")
        name
    end
end

# symbols pdflatex's utf8 input does not know, as math (works in every engine)
const _TEXMATH = Dict('≥' => "\\geq", '≤' => "\\leq", '±' => "\\pm", '×' => "\\times", '−' => "-",
                      '≈' => "\\approx", '≠' => "\\neq", '→' => "\\rightarrow", '←' => "\\leftarrow",
                      '∞' => "\\infty", '°' => "^\\circ", 'µ' => "\\mu", '√' => "\\surd", '·' => "\\cdot",
                      '†' => "\\dagger", '‡' => "\\ddagger")
const _GREEK = Dict(zip("αβγδεζηθικλμνξπρστυφχψωΓΔΘΛΞΠΣΦΨΩ",
                        ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa",
                         "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi",
                         "omega", "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Phi", "Psi", "Omega"]))

function _tikzesc(s::AbstractString)
    io = IOBuffer()
    for ch in s
        if haskey(_TEXMATH, ch)
            print(io, "\\ensuremath{", _TEXMATH[ch], "}")
        elseif haskey(_GREEK, ch)
            print(io, "\\ensuremath{\\", _GREEK[ch], "}")
        elseif ch == '\\'
            print(io, "\\textbackslash{}")
        elseif ch in ('{', '}', '$', '&', '#', '%', '_')
            print(io, '\\', ch)
        elseif ch == '^'
            print(io, "\\^{}")
        elseif ch == '~'
            print(io, "\\textasciitilde{}")
        else
            print(io, ch)
        end
    end
    return String(take!(io))
end

function _tikzpaint!(opts, w::TikZWriter, fill::RGBA, stroke::RGBA, lw; dash=nothing, cap="round", join="round")
    if isvisible(fill)
        push!(opts, "fill=" * _tcolor(w, fill))
        fill.a < 1 && push!(opts, "fill opacity=" * _num(fill.a))
    end
    if isvisible(stroke) && lw > 0
        push!(opts, "draw=" * _tcolor(w, stroke), "line width=" * _pt(w, lw))
        stroke.a < 1 && push!(opts, "draw opacity=" * _num(stroke.a))
        cap == "butt" || push!(opts, "line cap=" * (cap == "square" ? "rect" : cap))
        join == "miter" || push!(opts, "line join=" * join)
        d = _dashvec(dash, lw)
        if !isempty(d)
            push!(opts, "dash pattern=" * Base.join((string(isodd(k) ? "on " : "off ", _pt(w, v)) for (k, v) in enumerate(d)), ' '))
        end
    end
    return opts
end

_tikzcmd(w::TikZWriter, opts, body) = (isempty(opts) && return; print(w.io, "\\path[", Base.join(opts, ", "), "] ", body, ";\n"))

function _tikz!(w::TikZWriter, g::GroupPrim)
    isempty(g.class) || print(w.io, "% ", g.class, "\n")
    for p in g.children
        _tikz!(w, p)
    end
end

function _tikz!(w::TikZWriter, p::PathPrim)
    opts = _tikzpaint!(String[], w, p.fill, p.stroke, p.linewidth; p.dash, p.cap, p.join)
    isempty(opts) && return
    p.fillrule == "evenodd" && push!(opts, "even odd rule")
    io = IOBuffer()
    start = (0.0, 0.0)
    pen = :none                      # :none, :open, :closed
    for s in p.segs
        if s.op == 'M'
            print(io, ' ', _xy(w, s.x, s.y)); start = (s.x, s.y); pen = :open
        elseif s.op == 'L'
            pen === :closed && print(io, ' ', _xy(w, start...))
            print(io, " -- ", _xy(w, s.x, s.y)); pen = :open
        elseif s.op == 'A'
            pen === :closed && print(io, ' ', _xy(w, start...))
            print(io, " arc[start angle=", _num(-rad2deg(s.a1)), ", end angle=", _num(-rad2deg(s.a2)),
                  ", radius=", _pt(w, s.r), "]")
            pen = :open
        else
            pen === :open && print(io, " -- cycle")
            pen = :closed
        end
    end
    _tikzcmd(w, opts, String(take!(io)))
end

function _tikz!(w::TikZWriter, p::RectPrim)
    a = _xy(w, p.x, p.y); b = _xy(w, p.x + p.w, p.y + p.h)
    if !isempty(p.gradient)
        n = length(p.gradient)
        if n == 1
            _tikzcmd(w, ["fill=" * _tcolor(w, p.gradient[1])], "$a rectangle $b")
        else
            dx = p.w / (n - 1)
            for k in 1:n-1
                x1 = p.x + (k - 1) * dx
                x2 = k == n - 1 ? p.x + p.w : x1 + dx + 0.3     # overlap hides seams
                print(w.io, "\\shade[left color=", _tcolor(w, p.gradient[k]), ", right color=",
                      _tcolor(w, p.gradient[k+1]), "] ", _xy(w, x1, p.y), " rectangle ", _xy(w, x2, p.y + p.h), ";\n")
            end
        end
        return
    end
    opts = _tikzpaint!(String[], w, p.fill, p.stroke, p.linewidth; join="miter")
    p.rx > 0 && !isempty(opts) && push!(opts, "rounded corners=" * _pt(w, p.rx))
    _tikzcmd(w, opts, "$a rectangle $b")
end

function _tikz!(w::TikZWriter, p::CirclePrim)
    opts = _tikzpaint!(String[], w, p.fill, p.stroke, p.linewidth)
    _tikzcmd(w, opts, string(_xy(w, p.x, p.y), " circle[radius=", _pt(w, p.r), "]"))
end

# text is anchored on its baseline at the point the SVG puts it (see _baseline)
_tikzanchor(h::Symbol) = h === :center ? "base" : h === :left ? "base west" : "base east"

_tikzfont(w::TikZWriter, fs, bold, italic) =
    string("\\fontsize{", _num(fs), "}{", _num(1.2fs), "}\\selectfont\\PlotPhyloTreeFont", w.family,
           bold ? "\\bfseries" : "", italic ? "\\itshape" : "")

function _tikz!(w::TikZWriter, p::TextPrim)
    fs = w.s * p.fontsize
    font = _tikzfont(w, fs, p.bold, p.italic)
    base = ["anchor=" * _tikzanchor(p.halign), "inner sep=0pt", "outer sep=0pt", "font=" * font]
    p.angle == 0 || push!(base, "rotate=" * _num(-p.angle))
    txt = _tikzesc(p.text)
    x, y = _baseline(p)
    if isvisible(p.halo) && p.halowidth > 0
        # a halo: the text drawn in the halo colour, nudged in 8 directions, underneath
        r = p.halowidth / 2
        hc = _tcolor(w, p.halo)
        for k in 0:7
            a = k * π / 4
            print(w.io, "\\node[", Base.join(base, ", "), ", text=", hc, "] at ",
                  _xy(w, x + r * cos(a), y + r * sin(a)), " {", txt, "};\n")
        end
    end
    opts = push!(copy(base), "text=" * _tcolor(w, p.color))
    p.color.a < 1 && push!(opts, "text opacity=" * _num(p.color.a))
    print(w.io, "\\node[", Base.join(opts, ", "), "] at ", _xy(w, x, y), " {", txt, "};\n")
end

# Curved text along its arc with TikZ's `text along path` decoration, so the
# document font's own widths space the letters. Falls back to the layout's
# per-glyph placement for text TikZ cannot decorate (macros, halos).
function _tikz!(w::TikZWriter, p::ArcTextPrim)
    txt = _tikzesc(p.text)
    if w.curved !== :native || txt != p.text || isvisible(p.halo) || occursin('|', p.text)
        foreach(g -> _tikz!(w, g), p.glyphs)
        return
    end
    # baseline radius: the text is centred (vertically) on r; glyphs face outwards in
    # the upper half (reading clockwise) and inwards in the lower half
    rb = p.r - (p.clockwise ? 1 : -1) * 0.35 * p.fontsize
    W = textwidth_px(p.text, p.fontsize; p.bold, p.italic)
    span = clamp(1.6 * W / (2rb) + 0.15, 0.1, 0.95π)            # half-angle of the path, generous
    a1, a2 = p.clockwise ? (p.φ - span, p.φ + span) : (p.φ + span, p.φ - span)
    font = _tikzfont(w, w.s * p.fontsize, p.bold, p.italic)
    col = _tcolor(w, p.color)
    alpha = p.color.a < 1 ? "\\pgfsetfillopacity{" * _num(p.color.a) * "}" : ""
    print(w.io, "\\path[decorate, decoration={text along path, text align=center, text={|", font, "\\color{", col,
          "}", alpha, "|", txt, "}}] ", _xy(w, p.cx + rb * cos(a1), p.cy + rb * sin(a1)),
          " arc[start angle=", _num(-rad2deg(a1)), ", end angle=", _num(-rad2deg(a2)), ", radius=", _pt(w, rb), "];\n")
end

function _tikz!(w::TikZWriter, p::ImagePrim)
    w.nimages += 1
    name = _exportimage(p, w.imagedir, w.imageprefix, w.nimages, (".png", ".jpg", ".pdf"))
    name === nothing && return
    opac = p.opacity < 1 ? ", opacity=" * _num(p.opacity) : ""
    print(w.io, "\\node[inner sep=0pt, outer sep=0pt", opac, "] at ", _xy(w, p.x + p.w / 2, p.y + p.h / 2),
          " {\\includegraphics[width=", _pt(w, p.w), ", height=", _pt(w, p.h), ", keepaspectratio]{", name, "}};\n")
end

"""
    tikzstring(p; standalone=false, scale=1, font="", curvedtext=:native) -> String

The figure as TikZ code: a `tikzpicture` to `\\input` into a LaTeX document,
or with `standalone = true` a complete document that compiles on its own.

Geometry (branches, wedges, rings, symbols) is fixed by the layout, in bp
(1 px = 1 bp; `scale` multiplies every length, font sizes included). Text is
handed to LaTeX: labels are typeset in the **document's font** at the
layout's sizes, so changing the document font changes the tree's labels.
Ways to pick the font, from widest to narrowest scope:

- the picture uses the font current where it is `\\input` (e.g. wrap it in
  `{\\sffamily …}`);
- every label starts with `\\PlotPhyloTreeFont` (empty unless you define it,
  e.g. `\\newcommand\\PlotPhyloTreeFont{\\sffamily}` in the preamble);
- `font` adds LaTeX font code to this figure's labels.

Lay the tree out with the metrics of that font (`treeplot(…; metrics=:lmroman)`
for LaTeX's default, or [`fontmetrics`](@ref) for any font file) so label
bands and the legend fit the text LaTeX sets. Curved clade labels use TikZ's
`text along path`, spaced with the document font's own widths;
`curvedtext = :glyphs` places each letter where the layout put it instead.

Needs `\\usepackage{tikz}` and `\\usetikzlibrary{decorations.text}` (the
standalone document loads both, plus a font matching the layout metrics).
Images are written beside the file by [`savefig`](@ref) (`"tree.tex"` →
`tree-img-1.png` …); SVG images are converted to PDF, which needs the
Librsvg extension.
"""
tikzstring(p::TreePlot; kwargs...) = tikzdocument(scene(p); kwargs...)

# preamble lines loading a font that matches the layout metrics (pdfLaTeX)
function _tikzfontpreamble(m::FontMetrics)
    n = m.name
    n == "Helvetica" && return "\\usepackage{tgheros}\n\\renewcommand{\\familydefault}{\\sfdefault}\n"
    n == "Latin Modern Sans" && return "\\usepackage{lmodern}\n\\renewcommand{\\familydefault}{\\sfdefault}\n"
    n == "Latin Modern Roman" && return "\\usepackage{lmodern}\n"
    n == "Times" && return "\\usepackage{tgtermes}\n"
    return "\\usepackage{lmodern}\n% labels were laid out for $n: load it here (e.g. fontspec + lualatex)\n"
end

function tikzdocument(sc::Scene; standalone::Bool=false, scale::Real=1, font::AbstractString="",
                      curvedtext::Symbol=:native, imagedir=nothing, imageprefix::AbstractString="img")
    curvedtext in (:native, :glyphs) || throw(ArgumentError("curvedtext must be :native or :glyphs"))
    w = TikZWriter(IOBuffer(), Float64(scale), Dict{UInt32,String}(), IOBuffer(), String(font), curvedtext,
                   imagedir === nothing ? nothing : String(imagedir), String(imageprefix), 0)
    for p in sc.prims
        _tikz!(w, p)
    end
    body = String(take!(w.io))
    io = IOBuffer()
    if standalone
        print(io, "\\documentclass[tikz, border=0pt]{standalone}\n\\usepackage[T1]{fontenc}\n",
              _tikzfontpreamble(sc.metrics), "\\usepackage{graphicx}\n\\usetikzlibrary{decorations.text}\n",
              "\\begin{document}\n")
    end
    print(io, "% PlotPhyloTree figure: ", _num(w.s * sc.width), " x ", _num(w.s * sc.height),
          " bp; labels laid out for ", sc.metrics.name, "\n",
          "% needs \\usepackage{tikz} and \\usetikzlibrary{decorations.text}\n",
          "\\providecommand\\PlotPhyloTreeFont{}\n")
    print(io, "\\begin{tikzpicture}[x=1bp, y=1bp]\n")
    print(io, String(take!(w.colordefs)))
    bg = sc.background
    corners = string(_xy(w, sc.x0, sc.y0), " rectangle ", _xy(w, sc.x0 + sc.width, sc.y0 + sc.height))
    print(io, "\\useasboundingbox", isvisible(bg) ? "[fill={rgb,255:red,$(_byte(bg.r));green,$(_byte(bg.g));blue,$(_byte(bg.b))}]" : "",
          " ", corners, ";\n")
    print(io, body)
    print(io, "\\end{tikzpicture}\n")
    standalone && print(io, "\\end{document}\n")
    return String(take!(io))
end
