# The plot object, its geometry and the rendering pipeline.

abstract type Layer end

struct LegendEntry
    label::String
    kind::Symbol          # :marker, :patch, :line
    color::RGBA
    marker::Symbol
    size::Float64
    stroke::RGBA
end
LegendEntry(label, kind, color; marker=:circle, size=8.0, stroke=TRANSPARENT) =
    LegendEntry(String(label), kind, tocolor(color), marker, Float64(size), tocolor(stroke))

struct LegendSection
    title::String
    entries::Vector{LegendEntry}
    colorbar::Union{Nothing,Tuple{Vector{RGBA},Float64,Float64}}
end
LegendSection(title, entries::Vector{LegendEntry}) = LegendSection(String(title), entries, nothing)

"""
    TreePlot

A tree figure under construction: create it with [`treeplot`](@ref), add
layers with the `!` functions ([`highlight!`](@ref), [`support!`](@ref),
[`nodepies!`](@ref), …), then display it or [`savefig`](@ref) it.
"""
mutable struct TreePlot
    tree::PhyloTree
    layout::Symbol
    x::Vector{Float64}          # depth in tree units
    pos::Vector{Float64}        # tip-axis position
    opt::Dict{Symbol,Any}
    bcolor::Vector{RGBA}
    bwidth::Vector{Float64}
    bdash::Vector{Symbol}
    layers::Vector{Layer}
    legends::Vector{LegendSection}
end

const THEMES = Dict{Symbol,Dict{Symbol,Any}}(
    :light => Dict(:bg => "#ffffff", :fg => "#222222", :branch => "#3a3a3a", :muted => "#8a8a8a",
                   :grid => "#d9d9d9", :band => "#f3f3f3"),
    :dark => Dict(:bg => "#14161a", :fg => "#e8e8e8", :branch => "#d0d0d0", :muted => "#9a9a9a",
                  :grid => "#3a3d44", :band => "#1d2026"),
    :minimal => Dict(:bg => "none", :fg => "#222222", :branch => "#555555", :muted => "#999999",
                     :grid => "#e3e3e3", :band => "#f6f6f6"),
)

"""
    treeplot(tree; kwargs...) -> TreePlot

Start a tree figure. `tree` is a `PhyloTree`, a Newick string, or a
path to a Newick/Nexus file.

# Layout
- `layout = :rectangular` — or `:circular`, `:fan` (an open circle), or
  `:dendrogram` (rectangular, growing downwards).
- `branchstyle = :square` — elbows; `:round` (rounded corners), `:curved`
  (smooth sweeps) or `:slanted` (straight lines from parent to child).
- `cladogram = false` — ignore branch lengths and align the tips.
- `ladderize = false` — sort clades by size (`true`, or `:left`/`:right`).
- `direction = :right` — rectangular only: `:right`, `:left`, `:down`, `:up`.
- `openangle` — circular/fan: gap in degrees (default 6 for `:circular`, 180
  for `:fan`). `rotation = 0` — rotate the whole circle clockwise (degrees).
- `inner = 0` — circular: radius (px) of an empty hole at the centre.
- `rootedge = 0` — length in px of a stem drawn below the root.
- `radius`, `width`, `tipspacing` — size of the tree itself in px (the
  circle's radius to the furthest tip, or the depth and per-tip spacing of a
  rectangular tree). All are chosen from the number of tips by default.

# Branches
- `color` — a colour; a vector/dictionary/function of per-node values; or a
  `Symbol` naming a node annotation (e.g. `:rate`). Numbers are coloured
  with `colormap` over `colorrange` and get a colour bar; categories get
  `palette` colours and a legend.
- `linewidth` — a number or per-node values; `linestyle = :solid`.

# Text and theme
- `tiplabels = true`, `italic = false`, `align = false`, `fontsize` (auto).
- `font = "Helvetica Neue, Helvetica, Arial, sans-serif"`.
- `theme = :light` — or `:dark`, `:minimal` (transparent background).
- `background` — overrides the theme's background colour.
- `title`, `subtitle`, `legend = :auto` (`:right`, `:bottom`,
  `:topright`, `:topleft`, `:bottomright`, `:bottomleft`, `:none`),
  `legendtitle`, `margin = 16`.
"""
function treeplot(tree::PhyloTree; layout::Symbol=:rectangular, branchstyle::Symbol=:square,
                  cladogram::Bool=false, ladderize=false, direction::Symbol=:right,
                  openangle=nothing, rotation::Real=0, inner::Real=0, rootedge::Real=0,
                  radius=nothing, width=nothing, tipspacing=nothing,
                  color=nothing, linewidth=nothing, linestyle::Symbol=:solid,
                  colormap=:viridis, colorrange=nothing, palette=:default, colortitle="",
                  tiplabels::Bool=true, italic::Bool=false, align::Bool=false, fontsize=nothing,
                  font::AbstractString="Helvetica Neue, Helvetica, Arial, sans-serif",
                  theme::Symbol=:light, background=nothing, title=nothing, subtitle=nothing,
                  legend::Symbol=:auto, legendtitle=nothing, margin::Real=16)
    t = tree
    if ladderize !== false
        t = copy(tree)
        ladderize!(t; right=ladderize !== :left)
    end
    if layout === :dendrogram
        layout = :rectangular
        direction === :right && (direction = :down)
    end
    layout in (:rectangular, :circular, :fan) ||
        throw(ArgumentError("layout must be :rectangular, :circular, :fan or :dendrogram"))
    branchstyle in (:square, :round, :curved, :slanted) ||
        throw(ArgumentError("branchstyle must be :square, :round, :curved or :slanted"))
    direction in (:right, :left, :down, :up) ||
        throw(ArgumentError("direction must be :right, :left, :down or :up"))
    haskey(THEMES, theme) || throw(ArgumentError("theme must be one of $(collect(keys(THEMES)))"))

    x = rootdistance(t; cladogram)
    pos = _tippositions(t)
    n = ntips(t)
    th = copy(THEMES[theme])
    background === nothing || (th[:bg] = background)
    polar = layout !== :rectangular
    fs = fontsize === nothing ? _autofontsize(n, polar) : Float64(fontsize)
    opt = Dict{Symbol,Any}(
        :branchstyle => branchstyle, :direction => direction,
        :openangle => openangle === nothing ? (layout === :fan ? 180.0 : 6.0) : Float64(openangle),
        :rotation => Float64(rotation), :inner => Float64(inner), :rootedge => Float64(rootedge),
        :radius => radius, :width => width, :tipspacing => tipspacing,
        :fontsize => fs, :font => String(font), :theme => th,
        :title => title, :subtitle => subtitle, :legend => legend, :legendtitle => legendtitle,
        :margin => Float64(margin), :cladogram => cladogram, :fan => layout === :fan,
        :scalebar => nothing,
    )
    nn = nnodes(t)
    lw0 = n <= 80 ? 1.3 : n <= 250 ? 1.0 : n <= 800 ? 0.7 : 0.5
    p = TreePlot(t, polar ? :circular : :rectangular, x, pos, opt,
                 fill(tocolor(th[:branch]), nn), fill(lw0, nn), fill(linestyle, nn), Layer[], LegendSection[])
    color === nothing || colorbranches!(p, color; colormap, colorrange, palette, title=colortitle)
    linewidth === nothing || _setwidths!(p, linewidth)
    tiplabels && tiplabels!(p; italic, align)
    return p
end

treeplot(s::AbstractString; kwargs...) = treeplot(_loadtree(s); kwargs...)

function _loadtree(s::AbstractString)
    if isfile(s)
        head = lowercase(first(read(s, String), 200))
        return occursin("#nexus", head) ? readnexus(s) : readnewick(s)
    end
    return parsenewick(s)
end

_autofontsize(n, polar) = polar ? (n <= 60 ? 10.0 : n <= 150 ? 8.5 : n <= 400 ? 6.5 : 5.0) :
                                  (n <= 50 ? 11.0 : n <= 120 ? 9.0 : n <= 300 ? 7.0 : 5.0)

function _tippositions(t::PhyloTree)
    pos = zeros(nnodes(t))
    k = 0
    for i in postorder(t)
        if isleaf(t, i)
            # postorder visits tips in drawing order too
            k += 1
            pos[i] = k
        else
            ch = t.children[i]
            pos[i] = (pos[ch[1]] + pos[ch[end]]) / 2
        end
    end
    return pos
end

function _setwidths!(p::TreePlot, w)
    if w isa Real
        fill!(p.bwidth, w)
    else
        v = nodevalues(p, w)
        vals = [x for x in v if x isa Real]
        isempty(vals) && return p
        lo, hi = extrema(vals)
        for i in eachindex(v)
            v[i] isa Real || continue
            # map numbers to 0.5–4 px unless they already look like widths
            p.bwidth[i] = (lo >= 0.2 && hi <= 8) ? v[i] : 0.5 + 3.5 * (hi > lo ? (v[i] - lo) / (hi - lo) : 0.5)
        end
    end
    return p
end

# --- per-node data ------------------------------------------------------------------

"""
    nodevalues(p, v) -> Vector{Any}

Expand `v` to one value per node (`nothing` where missing). `v` may be a
dictionary keyed by node references (labels, indices or collections of tip
labels meaning their MRCA), a vector over all nodes, a vector over tips in
drawing order, a `Symbol` naming a node annotation, a function of the node
index, or a single value for every node.
"""
function nodevalues(p::TreePlot, v)
    t = p.tree
    n = nnodes(t)
    out = Vector{Any}(nothing, n)
    if v isa AbstractDict
        for (k, val) in v
            out[nodeindex(t, k)] = val
        end
    elseif v isa Symbol && any(d -> haskey(d, v), t.data)
        for i in 1:n
            out[i] = get(t.data[i], v, nothing)
        end
    elseif v isa AbstractVector && !(v isa AbstractString)
        if length(v) == n
            out .= v
        elseif length(v) == ntips(t)
            for (k, i) in enumerate(tips(t))
                out[i] = v[k]
            end
        else
            throw(ArgumentError("a vector of values needs one entry per node ($n) or per tip ($(ntips(t)))"))
        end
    elseif v isa Function
        for i in 1:n
            out[i] = v(i)
        end
    else
        fill!(out, v)
    end
    return out
end

_iscolorlike(x) = x isa RGBA || x isa Tuple || (x isa Integer && !(x isa Bool)) || (x isa Union{Symbol,AbstractString} && _parses_as_color(x)) ||
                  (hasproperty(x, :r) && hasproperty(x, :g) && hasproperty(x, :b))
_parses_as_color(x) = try
    tocolor(x); true
catch
    false
end

"""
Turn per-node values into colours. Returns `(colors, legendsection)`, where
`colors[i] === nothing` for nodes without a value.
"""
function _colorize(vals::Vector{Any}; colormap=:viridis, colorrange=nothing, palette=:default, title="",
                   levels=nothing)
    present = [v for v in vals if v !== nothing && !(v isa Real && isnan(v))]
    cols = Vector{Union{Nothing,RGBA}}(nothing, length(vals))
    isempty(present) && return cols, nothing
    if all(v -> v isa Real && !(v isa Bool), present)
        lo, hi = colorrange === nothing ? extrema(present) : colorrange
        cm = PlotPhyloTree.colormap(colormap)
        for (i, v) in enumerate(vals)
            (v isa Real && !isnan(v)) || continue
            cols[i] = cmap(cm, hi > lo ? (v - lo) / (hi - lo) : 0.5)
        end
        return cols, LegendSection(String(title), LegendEntry[], (cm, Float64(lo), Float64(hi)))
    elseif all(_iscolorlike, present)
        for (i, v) in enumerate(vals)
            v === nothing || (cols[i] = tocolor(v))
        end
        return cols, nothing
    else
        cats = levels === nothing ? _levels(present) : collect(levels)
        pal = PlotPhyloTree.palette(palette, length(cats))
        lookup = Dict(c => pal[k] for (k, c) in enumerate(cats))
        for (i, v) in enumerate(vals)
            v === nothing || (cols[i] = get(lookup, v, RGBA(0.6, 0.6, 0.6, 1)))
        end
        entries = [LegendEntry(string(c), :patch, pal[k]) for (k, c) in enumerate(cats)]
        return cols, LegendSection(String(title), entries)
    end
end

function _levels(v)
    u = unique(v)
    try
        sort!(u)
    catch
    end
    return u
end

# --- geometry -------------------------------------------------------------------------

mutable struct Ctx
    p::TreePlot
    coord::Coord
    r::Vector{Float64}          # depth in px of every node
    R::Float64                  # depth in px of the furthest tip
    r0::Float64                 # depth in px of the root
    scale::Float64              # px per tree unit
    fs::Float64
    th::Dict{Symbol,Any}
    bands::Dict{Any,Tuple{Float64,Float64}}
    textend::Float64            # outer edge of label-like bands
    outer::Float64              # outer edge of all bands
end

function geometry(p::TreePlot)
    t = p.tree
    n = ntips(t)
    o = p.opt
    fs = o[:fontsize]
    xmax = maximum(p.x)
    labelled = any(l -> l isa TipLabels, p.layers)
    if p.layout === :circular
        span = deg2rad(360 - clamp(o[:openangle], 0, 359))
        gapcentre = o[:fan] ? π / 2 : Float64(π)
        φ0 = gapcentre + deg2rad(o[:openangle]) / 2 + deg2rad(o[:rotation])
        # room for every tip label around the circle, or a compact circle without them
        R = o[:radius] !== nothing ? Float64(o[:radius]) :
            labelled ? max(170.0, n * fs * 1.3 / span) : max(220.0, n * 3.0 / span)
        coord = Polar(φ0, span / n)
        r0 = o[:inner] + o[:rootedge]
    else
        sp = o[:tipspacing] !== nothing ? Float64(o[:tipspacing]) :
             labelled ? max(fs * 1.45, 2.0) : clamp(700 / n, 1.5, fs * 1.45)
        R = o[:width] === nothing ? clamp(n * sp * 0.8, 240.0, 640.0) : Float64(o[:width])
        coord = Cartesian(o[:direction], sp)
        r0 = o[:rootedge]
    end
    scale = xmax > 0 ? (R - r0) / xmax : 0.0
    r = [r0 + x * scale for x in p.x]
    ctx = Ctx(p, coord, r, R, r0, scale, fs, o[:theme], Dict{Any,Tuple{Float64,Float64}}(), R, R)
    _allocate_bands!(ctx)
    return ctx
end

# layers that occupy a band outside the tips, in the order they were added
bandkey(::Layer) = nothing
bandwidth(::Layer, ::Ctx, start) = 0.0
bandgap(::Layer) = 6.0
istextband(::Layer) = false
zorder(::Layer) = 5.0
suborder(::Layer, p) = 0.0
legendsections(::Layer, ::Ctx) = LegendSection[]

function _allocate_bands!(ctx::Ctx)
    order = Any[]
    members = Dict{Any,Vector{Layer}}()
    for l in ctx.p.layers
        k = bandkey(l)
        k === nothing && continue
        haskey(members, k) || (push!(order, k); members[k] = Layer[])
        push!(members[k], l)
    end
    # clade-label rings go out in order of level, wherever they were added
    slots = findall(k -> k isa Tuple && first(k) === :cladelabel, order)
    order[slots] = sort(order[slots]; by=last)
    cursor = ctx.R
    textend = ctx.R
    for k in order
        ls = members[k]
        gap = maximum(bandgap(l) for l in ls)
        start = cursor + gap
        w = maximum(bandwidth(l, ctx, start) for l in ls)
        ctx.bands[k] = (start, start + w)
        cursor = start + w
        any(istextband, ls) && (textend = cursor)
    end
    ctx.textend = textend
    ctx.outer = cursor
    return ctx
end

band(ctx::Ctx, l::Layer) = ctx.bands[bandkey(l)]

# --- rendering --------------------------------------------------------------------------

"""
    scene(p::TreePlot) -> Scene

Lay out `p` and record everything it draws; the backends translate the result.
"""
function scene(p::TreePlot)
    ctx = geometry(p)
    c = Canvas()
    layers = sort(p.layers; by=l -> (zorder(l), suborder(l, p)))   # stable within a level
    k = 1
    while k <= length(layers) && zorder(layers[k]) < 3
        draw!(c, layers[k], ctx); k += 1
    end
    _drawbranches!(c, ctx)
    while k <= length(layers)
        draw!(c, layers[k], ctx); k += 1
    end
    resolve_labels!(c)          # movable labels go where they clash with nothing
    _drawscalebar!(c, ctx)
    _drawlegend!(c, ctx)
    _drawtitle!(c, ctx)
    m = p.opt[:margin]
    b = c.bbox
    isempty_bbox(b) && (b = BBox(0, 0, 1, 1))
    x0 = floor(b.xmin - m); y0 = floor(b.ymin - m)
    W = ceil(b.xmax + m - x0); H = ceil(b.ymax + m - y0)
    return Scene(c.prims, x0, y0, W, H, tocolor(ctx.th[:bg]), p.opt[:font])
end

"""
    render(p::TreePlot) -> String

The SVG document for `p`.
"""
render(p::TreePlot) = svgdocument(scene(p))

# --- branches ------------------------------------------------------------------------

function _drawbranches!(c::Canvas, ctx::Ctx)
    p = ctx.p
    t = p.tree
    co = ctx.coord
    style = p.opt[:branchstyle]
    groups = Dict{Tuple{RGBA,Float64,Symbol},PathBuilder}()
    order = Tuple{RGBA,Float64,Symbol}[]
    for i in preorder(t)
        key = (p.bcolor[i], p.bwidth[i], p.bdash[i])
        pb = get!(groups, key) do
            push!(order, key)
            PathBuilder()
        end
        if i == t.root
            re = p.opt[:rootedge]
            if re > 0
                move!(pb, co, ctx.r[i] - re, p.pos[i])
                line!(pb, co, ctx.r[i], p.pos[i])
            end
            continue
        end
        j = t.parent[i]
        _branchpath!(pb, co, style, ctx.r[j], p.pos[j], ctx.r[i], p.pos[i])
    end
    group(c, "branches") do
        for key in order
            col, lw, dash = key
            path!(c, groups[key]; stroke=col, linewidth=lw, dash=dash === :solid ? nothing : dash)
        end
    end
end

function _branchpath!(pb, co::Coord, style::Symbol, rp, pp, ri, pi)
    if style === :slanted
        move!(pb, co, rp, pp)
        line!(pb, co, ri, pi)
    elseif style === :square || abs(pi - pp) < 1e-9
        move!(pb, co, rp, pp)
        across!(pb, co, rp, pp, pi)
        line!(pb, co, ri, pi)
    else
        dr = ri - rp
        dpos = pi - pp
        if style === :round
            # corner size in px, no larger than the branch or the arc it turns from
            cr = min(6.0, dr, abs(dpos) * pxperpos(co, rp))
            cr < 0.5 && return _branchpath!(pb, co, :square, rp, pp, ri, pi)
            cp = cr / pxperpos(co, rp) * sign(dpos)
        else # :curved
            cr = min(dr, max(10.0, 0.6 * dr), 60.0)
            cp = dpos
        end
        move!(pb, co, rp, pp)
        abs(dpos - cp) > 1e-9 && across!(pb, co, rp, pp, pi - cp)
        # quarter ellipse from (rp, pi - cp) to (rp + cr, pi)
        nseg = co isa Polar ? 14 : 10
        for k in 1:nseg
            θ = (π / 2) * k / nseg
            line!(pb, co, rp + cr * (1 - cos(θ)), pi - cp + cp * sin(θ))
        end
        line!(pb, co, ri, pi)
    end
    return pb
end

"""
    colorbranches!(p, values; colormap=:viridis, colorrange=nothing, palette=:default, title="")

Colour every branch by a per-node value (see [`nodevalues`](@ref)); numbers
use `colormap` and add a colour bar, categories use `palette` and add a
legend, colours are used as given.
"""
function colorbranches!(p::TreePlot, v; colormap=:viridis, colorrange=nothing, palette=:default, title="")
    if _iscolorlike(v) && !(v isa Symbol && any(d -> haskey(d, v), p.tree.data))
        fill!(p.bcolor, tocolor(v))
        return p
    end
    cols, leg = _colorize(nodevalues(p, v); colormap, colorrange, palette, title)
    for i in eachindex(cols)
        cols[i] === nothing || (p.bcolor[i] = cols[i])
    end
    leg === nothing || push!(p.legends, leg)
    return p
end

"""
    colorclade!(p, clade, color; linewidth=nothing, label=nothing, tiplabels=true)

Colour the branches (and, with `tiplabels = true`, the tip labels) of
`clade` — a node, tip label or collection of tip labels whose MRCA is used.
With `label`, add a legend entry.
"""
function colorclade!(p::TreePlot, clade, color; linewidth=nothing, label=nothing, tiplabels::Bool=true,
                     stem::Bool=true)
    t = p.tree
    node = nodeindex(t, clade)
    col = tocolor(color)
    nodes = stem ? preorder(t, node) : descendants(t, node)
    for i in nodes
        p.bcolor[i] = col
        linewidth === nothing || (p.bwidth[i] = linewidth)
    end
    if tiplabels
        for l in p.layers
            l isa TipLabels && (for i in tips(t, node); l.colors[i] = col; end)
        end
    end
    label === nothing || _addlegend!(p, "", LegendEntry(String(label), :line, col; size=3))
    return p
end

function _addlegend!(p::TreePlot, title::AbstractString, e::LegendEntry)
    for (k, s) in enumerate(p.legends)
        if s.title == title && s.colorbar === nothing
            push!(s.entries, e)
            return p
        end
    end
    push!(p.legends, LegendSection(String(title), [e]))
    return p
end
