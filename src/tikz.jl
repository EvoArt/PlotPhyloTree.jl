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
_generic(font::AbstractString) = (f = lowercase(font); occursin("monospace", f) ? :mono :
                                  occursin("sans", f) ? :sans : occursin("serif", f) ? :serif : :sans)

# --- TikZ -----------------------------------------------------------------------------

mutable struct TikZWriter
    io::IOBuffer
    s::Float64                         # scale
    colors::Dict{UInt32,String}
    colordefs::IOBuffer
    family::String                     # \sffamily etc.
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

function _tikzanchor(h::Symbol, v::Symbol)
    vv = v === :center ? "mid" : v === :baseline ? "base" : v === :top ? "north" : "south"
    h === :center && return vv
    return string(vv, ' ', h === :left ? "west" : "east")
end

function _tikz!(w::TikZWriter, p::TextPrim)
    fs = w.s * p.fontsize
    font = string("\\fontsize{", _num(fs), "}{", _num(1.2fs), "}\\selectfont", w.family,
                  p.bold ? "\\bfseries" : "", p.italic ? "\\itshape" : "")
    base = ["anchor=" * _tikzanchor(p.halign, p.valign), "inner sep=0pt", "outer sep=0pt", "font=" * font]
    p.angle == 0 || push!(base, "rotate=" * _num(-p.angle))
    txt = _tikzesc(p.text)
    if isvisible(p.halo) && p.halowidth > 0
        # a halo: the text drawn in the halo colour, nudged in 8 directions, underneath
        r = p.halowidth / 2
        hc = _tcolor(w, p.halo)
        for k in 0:7
            a = k * π / 4
            print(w.io, "\\node[", Base.join(base, ", "), ", text=", hc, "] at ",
                  _xy(w, p.x + r * cos(a), p.y + r * sin(a)), " {", txt, "};\n")
        end
    end
    opts = push!(copy(base), "text=" * _tcolor(w, p.color))
    p.color.a < 1 && push!(opts, "text opacity=" * _num(p.color.a))
    print(w.io, "\\node[", Base.join(opts, ", "), "] at ", _xy(w, p.x, p.y), " {", txt, "};\n")
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
    tikzstring(p; standalone=false, scale=1, font=nothing) -> String

The figure as TikZ code: a `tikzpicture` environment to `\\input` into a
LaTeX document (needs `\\usepackage{tikz}`), or with `standalone = true` a
complete document that compiles on its own (`pdflatex`, `lualatex`).

One px of the layout becomes one bp (1/72 in), and `scale` multiplies every
length, including font sizes and line widths — use it to fit a column
(`\\resizebox` works too). Labels are set in the document's font at the
layout's sizes: `font` is LaTeX font code added to every label (e.g.
`"\\\\sffamily"`); by default the figure's `font` option picks `\\sffamily`,
`\\rmfamily` or `\\ttfamily`.

Images are written beside the file by [`savefig`](@ref) (`"tree.tex"` →
`tree-img-1.png` …); SVG images are converted to PDF, which needs the
Librsvg extension.
"""
tikzstring(p::TreePlot; kwargs...) = tikzdocument(scene(p); kwargs...)

function tikzdocument(sc::Scene; standalone::Bool=false, scale::Real=1, font=nothing,
                      imagedir=nothing, imageprefix::AbstractString="img")
    fam = font !== nothing ? String(font) :
          (g = _generic(sc.font); g === :sans ? "\\sffamily" : g === :mono ? "\\ttfamily" : "\\rmfamily")
    w = TikZWriter(IOBuffer(), Float64(scale), Dict{UInt32,String}(), IOBuffer(), fam,
                   imagedir === nothing ? nothing : String(imagedir), String(imageprefix), 0)
    for p in sc.prims
        _tikz!(w, p)
    end
    body = String(take!(w.io))
    io = IOBuffer()
    if standalone
        print(io, "\\documentclass[tikz, border=0pt]{standalone}\n",
              "\\usepackage[T1]{fontenc}\n\\usepackage{lmodern}\n\\usepackage{graphicx}\n",
              "\\begin{document}\n")
    end
    print(io, "% PlotPhyloTree figure: ", _num(w.s * sc.width), " x ", _num(w.s * sc.height), " bp\n")
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
