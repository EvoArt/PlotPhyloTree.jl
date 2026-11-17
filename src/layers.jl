# Layers that decorate a tree.

function _selectnodes(p::TreePlot, nodes)
    t = p.tree
    nodes === :internal && return internalnodes(t)
    nodes === :tips && return tips(t)
    nodes === :all && return preorder(t)
    nodes isa Union{AbstractString,Integer} && return [nodeindex(t, nodes)]
    return [nodeindex(t, n) for n in nodes]
end

_fg(ctx::Ctx) = tocolor(ctx.th[:fg])
_bgcolor(ctx::Ctx) = (b = tocolor(ctx.th[:bg]); isvisible(b) ? b : RGBA(1, 1, 1, 1))

# pos extent of the tips below a node
function _posrange(p::TreePlot, node::Int)
    ts = tips(p.tree, node)
    return minimum(p.pos[ts]), maximum(p.pos[ts])
end

# =========================================================================================
# tip labels
# =========================================================================================

mutable struct TipLabels <: Layer
    text::Vector{String}
    colors::Vector{Union{Nothing,RGBA}}
    fontsize::Float64
    italic::Bool
    bold::Bool
    align::Bool
    offset::Float64
    leader::Bool
    leadercolor::Any
end

bandkey(::TipLabels) = :tiplabels
bandgap(::TipLabels) = 0.0
istextband(::TipLabels) = true
zorder(::TipLabels) = 7.0

"""
    tiplabels!(p; text=nothing, italic=false, bold=false, align=false, offset=4,
               color=nothing, fontsize=nothing, underscores=false, leader=align,
               colormap=:viridis, palette=:default)

Set the tip labels (replacing the default ones). `text` changes what is
written (a dictionary, vector, function of the node index, or annotation
key); by default the node labels, with underscores shown as spaces unless
`underscores = true`. `align = true` lines the labels up at the outermost tip
with dotted leader lines. `color` may be a colour or per-tip values.
"""
function tiplabels!(p::TreePlot; text=nothing, italic::Bool=false, bold::Bool=false, align::Bool=false,
                    offset::Real=4, color=nothing, fontsize=nothing, underscores::Bool=false,
                    leader::Bool=align, leadercolor=nothing, colormap=:viridis, palette=:default)
    t = p.tree
    n = nnodes(t)
    txt = fill("", n)
    vals = text === nothing ? nothing : nodevalues(p, text)
    for i in tips(t)
        s = vals === nothing ? t.label[i] : (vals[i] === nothing ? "" : string(vals[i]))
        txt[i] = underscores ? s : replace(s, '_' => ' ')
    end
    cols = Vector{Union{Nothing,RGBA}}(nothing, n)
    if color !== nothing
        if _iscolorlike(color) && !(color isa Symbol && any(d -> haskey(d, color), t.data))
            fill!(cols, tocolor(color))
        else
            c2, leg = _colorize(nodevalues(p, color); colormap, palette)
            cols .= c2
            leg === nothing || push!(p.legends, leg)
        end
    end
    l = TipLabels(txt, cols, fontsize === nothing ? NaN : Float64(fontsize), italic, bold, align,
                  Float64(offset), leader, leadercolor)
    k = findfirst(x -> x isa TipLabels, p.layers)
    k === nothing ? push!(p.layers, l) : (p.layers[k] = l)
    return p
end

"""    notiplabels!(p)  remove the tip labels."""
notiplabels!(p::TreePlot) = (filter!(l -> !(l isa TipLabels), p.layers); p)

_fs(l, ctx) = isnan(l.fontsize) ? ctx.fs : l.fontsize

function _labelstart(l::TipLabels, ctx::Ctx, i::Int, start::Float64)
    (l.align || start > ctx.R + 1e-6) && return start + l.offset
    return ctx.r[i] + l.offset
end

function bandwidth(l::TipLabels, ctx::Ctx, start)
    fs = _fs(l, ctx)
    e = start
    for i in tips(ctx.p.tree)
        e = max(e, _labelstart(l, ctx, i, start) + textwidth_px(l.text[i], fs; bold=l.bold, italic=l.italic))
    end
    return e - start
end

function draw!(c::Canvas, l::TipLabels, ctx::Ctx)
    p = ctx.p
    co = ctx.coord
    fs = _fs(l, ctx)
    start = band(ctx, l)[1]
    fg = _fg(ctx)
    lc = l.leadercolor === nothing ? withalpha(ctx.th[:muted], 0.8) : tocolor(l.leadercolor)
    if l.leader
        group(c, "leaders") do
            pb = PathBuilder()
            for i in tips(p.tree)
                rs = _labelstart(l, ctx, i, start)
                if rs - ctx.r[i] > l.offset + 4
                    move!(pb, co, ctx.r[i] + 2, p.pos[i])
                    line!(pb, co, rs - 2, p.pos[i])
                end
            end
            path!(c, pb; stroke=lc, linewidth=0.6, dash=:dot)
        end
    end
    group(c, "tiplabels") do
        for i in tips(p.tree)
            isempty(l.text[i]) && continue
            rs = _labelstart(l, ctx, i, start)
            ang, ha = radial_text_params(co, p.pos[i])
            x, y = xy(co, rs, p.pos[i])
            col = l.colors[i] === nothing ? fg : l.colors[i]
            text!(c, x, y, l.text[i]; fontsize=fs, angle=ang, halign=ha, color=col, italic=l.italic, bold=l.bold)
        end
    end
end

# =========================================================================================
# clade highlights
# =========================================================================================

struct Highlight <: Layer
    node::Int
    color::RGBA
    from::Any
    to::Any
    extend::Float64
    stroke::RGBA
    linewidth::Float64
    corner::Float64
    level::Int            # level of its clade label (0: none)
end
zorder(::Highlight) = 1.0
suborder(l::Highlight, p) = -Float64(length(tips(p.tree, l.node)))   # nested clades on top

"""
    highlight!(p, clade; color=auto, alpha=0.2, label=nothing, from=:stem, to=:labels,
               stroke=nothing, linewidth=1, branches=false, kwargs...)
    highlight!(p, clades::AbstractDict; palette=:default, kwargs...)

Shade the region behind `clade` (a node, tip label or collection of tip
labels whose MRCA is used), as a wedge in circular layouts and a rounded box
in rectangular ones.

- `color` — the colour, drawn at opacity `alpha`; by default the next colour of
  the palette.
- `label` — also add a [`cladelabel!`](@ref) in the same colour (extra
  keywords such as `level`, `fontsize` and `along` go to it).
- `from` — where the shading starts: `:stem` (half-way along the branch
  above the clade), `:node`, `:root`, or a distance in px before the node.
- `to` — where it ends: `:labels` (past the tip labels and its own clade
  label, or every label if it has none), `:tips`, `:all` (past every ring),
  or a distance in px beyond the furthest tip.
- `branches = true` also colours the clade's branches and tip labels.

The dictionary form highlights several clades, `label => clade`.
"""
function highlight!(p::TreePlot, clade; color=nothing, alpha::Real=0.2, label=nothing, from=:stem,
                    to=:labels, extend::Real=0, stroke=nothing, linewidth::Real=1, corner::Real=4,
                    branches::Bool=false, legend::Bool=false, labelcolor=nothing, kwargs...)
    node = nodeindex(p.tree, clade)
    k = count(l -> l isa Highlight, p.layers)
    base = color === nothing ? palette(:default)[mod1(k + 1, 10)] : tocolor(color)
    fillc = RGBA(base.r, base.g, base.b, base.a * alpha)
    st = stroke === nothing ? TRANSPARENT : stroke === true ? withalpha(base, 0.6) : tocolor(stroke)
    haslabel = label !== nothing && !legend
    level = haslabel ? Int(get(kwargs, :level, 1)) : 0
    push!(p.layers, Highlight(node, fillc, from, to, Float64(extend), st, Float64(linewidth), Float64(corner),
                              level))
    branches && colorclade!(p, node, darken(base, 0.1))
    if label !== nothing
        if legend
            _addlegend!(p, "", LegendEntry(String(label), :patch, withalpha(base, max(alpha, 0.35))))
        else
            cladelabel!(p, node, String(label); color=labelcolor === nothing ? base : labelcolor, kwargs...)
        end
    end
    return p
end

function highlight!(p::TreePlot, clades::AbstractDict; palette=:default, colors=nothing, kwargs...)
    pal = colors === nothing ? PlotPhyloTree.palette(palette, length(clades)) : tocolor.(colors)
    ks = collect(keys(clades))
    clades isa Dict && sort!(ks; by=k -> _posrange(p, nodeindex(p.tree, clades[k]))[1])
    for (j, k) in enumerate(ks)
        highlight!(p, clades[k]; color=pal[mod1(j, length(pal))], label=k, kwargs...)
    end
    return p
end
highlight!(p::TreePlot, clades::AbstractVector{<:Pair}; kwargs...) =
    highlight!(p, _OrderedPairs(clades); kwargs...)

# a tiny insertion-ordered dictionary for `label => clade` pairs
struct _OrderedPairs{K,V} <: AbstractDict{K,V}
    pairs::Vector{Pair{K,V}}
end
Base.iterate(d::_OrderedPairs, s...) = iterate(d.pairs, s...)
Base.length(d::_OrderedPairs) = length(d.pairs)
Base.keys(d::_OrderedPairs) = first.(d.pairs)
Base.getindex(d::_OrderedPairs, k) = last(d.pairs[findfirst(x -> first(x) == k, d.pairs)])

function _hl_from(ctx::Ctx, node::Int, from)
    t = ctx.p.tree
    r = ctx.r[node]
    from === :node && return max(r - 4, 0.0)
    from === :root && return ctx.r0
    if from === :stem
        par = t.parent[node]
        par == 0 && return max(r - 4, 0.0)
        return max((ctx.r[par] + r) / 2, r - 40)
    end
    from isa Real && return max(r - from, 0.0)
    throw(ArgumentError("from must be :stem, :node, :root or a number of px"))
end

function _hl_to(ctx::Ctx, to, level::Int=0)
    if to === :labels
        k = (:cladelabel, level)
        return (level > 0 && haskey(ctx.bands, k) ? ctx.bands[k][2] : ctx.textend) + 4
    end
    to === :tips && return ctx.R + 4
    to === :all && return ctx.outer + 4
    to isa Real && return ctx.R + to
    throw(ArgumentError("to must be :labels, :tips, :all or a number of px"))
end

function draw!(c::Canvas, l::Highlight, ctx::Ctx)
    p = ctx.p
    co = ctx.coord
    a, b = _posrange(p, l.node)
    r1 = _hl_from(ctx, l.node, l.from)
    r2 = _hl_to(ctx, l.to, l.level)
    if co isa Polar
        pb = PathBuilder()
        region!(pb, co, r1, r2, a - 0.5 - l.extend, b + 0.5 + l.extend)
        path!(c, pb; fill=l.color, stroke=l.stroke, linewidth=l.linewidth, class="highlight")
    else
        x1, y1 = xy(co, r1, a - 0.48 - l.extend)
        x2, y2 = xy(co, r2, b + 0.48 + l.extend)
        rect!(c, min(x1, x2), min(y1, y2), abs(x2 - x1), abs(y2 - y1); fill=l.color, stroke=l.stroke,
              linewidth=l.linewidth, rx=l.corner, class="highlight")
    end
end

# =========================================================================================
# clade labels (bar + text outside the tips)
# =========================================================================================

struct CladeLabel <: Layer
    node::Int
    text::String
    color::RGBA
    textcolor::Union{Nothing,RGBA}
    level::Int
    fontsize::Float64
    bold::Bool
    italic::Bool
    bar::Bool
    barwidth::Float64
    along::Union{Nothing,Bool}
    gap::Float64
end

bandkey(l::CladeLabel) = (:cladelabel, l.level)
bandgap(l::CladeLabel) = l.gap
istextband(::CladeLabel) = true
zorder(::CladeLabel) = 7.0

# along the bar by default in circular layouts and in trees growing up or down
_along(l::CladeLabel, ctx::Ctx) = l.along === nothing ? !_sideways(ctx.coord) : l.along
_sideways(co::Coord) = co isa Cartesian && co.dir in (:right, :left)

# shrink (to `minscale` of the size) and then shorten `s` so it fits in `avail` px
function _fittext(s::AbstractString, fs::Float64, avail::Float64; bold=false, minscale=0.65)
    w = textwidth_px(s, fs; bold)
    w <= avail && return String(s), fs
    fs2 = max(fs * avail / w, fs * minscale)
    textwidth_px(s, fs2; bold) <= avail && return String(s), fs2
    ch = collect(s)
    while length(ch) > 1 && textwidth_px(String(ch) * "…", fs2; bold) > avail
        pop!(ch)
    end
    return rstrip(String(ch)) * "…", fs2
end

"""
    cladelabel!(p, clade, text; color=:fg, textcolor=nothing, level=1, fontsize=auto,
                bold=true, italic=false, bar=true, barwidth=3, along=auto, gap=6)

Label a clade with a bar spanning its tips and a name beyond the tips (and
beyond the tip labels). Labels with the same `level` share a ring; higher
levels sit further out, as for nested taxonomic ranks. In circular layouts
the name follows the arc (`along = true`); set `along = false` for radial
text.
"""
function cladelabel!(p::TreePlot, clade, text::AbstractString; color=nothing, textcolor=nothing,
                     level::Integer=1, fontsize=nothing, bold::Bool=true, italic::Bool=false, bar::Bool=true,
                     barwidth::Real=3, along=nothing, gap::Real=6)
    node = nodeindex(p.tree, clade)
    col = color === nothing ? tocolor(p.opt[:theme][:fg]) : tocolor(color)
    fs = fontsize === nothing ? NaN : Float64(fontsize)
    tc = textcolor === nothing ? nothing : tocolor(textcolor)
    push!(p.layers, CladeLabel(node, String(text), col, tc, level, fs, bold, italic, bar, Float64(barwidth),
                               along, Float64(gap)))
    return p
end

_clfs(l::CladeLabel, ctx) = isnan(l.fontsize) ? ctx.fs * 1.1 : l.fontsize

function bandwidth(l::CladeLabel, ctx::Ctx, start)
    fs = _clfs(l, ctx)
    bw = l.bar ? l.barwidth + 4 : 0.0
    return _along(l, ctx) ? bw + fs * 1.15 : bw + textwidth_px(l.text, fs; bold=l.bold) + 2
end

function draw!(c::Canvas, l::CladeLabel, ctx::Ctx)
    p = ctx.p
    co = ctx.coord
    a, b = _posrange(p, l.node)
    start = band(ctx, l)[1]
    fs = _clfs(l, ctx)
    tcol = l.textcolor === nothing ? darken(l.color, 0.15) : l.textcolor
    inset = co isa Polar ? 0.12 : 0.15
    group(c, "cladelabel") do
        if l.bar
            pb = PathBuilder()
            rb = start + l.barwidth / 2
            if co isa Polar
                move!(pb, co, rb, a - 0.5 + inset)
                across!(pb, co, rb, a - 0.5 + inset, b + 0.5 - inset)
            else
                move!(pb, co, rb, a - 0.5 + inset)
                line!(pb, co, rb, b + 0.5 - inset)
            end
            path!(c, pb; stroke=l.color, linewidth=l.barwidth, cap="butt")
        end
        rt = start + (l.bar ? l.barwidth + 4 : 0.0)
        mid = (a + b) / 2
        if _along(l, ctx)
            rm = rt + fs * 0.5
            # the clade's span (plus a little) so neighbouring labels never overlap
            s, fs2 = _fittext(l.text, fs, (b - a + 1 - 2inset) * pxperpos(co, rm) + 4; bold=l.bold)
            if co isa Polar
                _arctext!(c, co, rm, mid, s; fontsize=fs2, color=tcol, bold=l.bold, italic=l.italic)
            else
                ang = rad2deg(outangle(co, mid)) - 90
                ang < -90 && (ang += 180)
                x, y = xy(co, rm, mid)
                text!(c, x, y, s; fontsize=fs2, angle=ang, halign=:center, color=tcol, bold=l.bold,
                      italic=l.italic)
            end
        else
            # radial text: its height must fit the clade's span
            span = (b - a + 1) * pxperpos(co, rt)
            fs2 = clamp(span / 1.05, fs * 0.65, fs)
            ang, ha = radial_text_params(co, mid)
            x, y = xy(co, rt, mid)
            text!(c, x, y, l.text; fontsize=fs2, angle=ang, halign=ha, color=tcol, bold=l.bold, italic=l.italic)
        end
    end
end

# glyph-by-glyph text along a circle, centred on `pos`, reading left to right
function _arctext!(c::Canvas, co::Polar, r, pos, s::AbstractString; fontsize, color, bold=false,
                   italic=false, halo=nothing)
    arctext!(c, 0.0, 0.0, r, angle(co, pos), s; fontsize, color, bold, italic, halo)
end

# =========================================================================================
# node and tip points (and support symbols)
# =========================================================================================

struct NodePoints <: Layer
    nodes::Vector{Int}
    colors::Vector{RGBA}
    markers::Vector{Symbol}
    sizes::Vector{Float64}
    stroke::RGBA
    strokewidth::Float64
    offset::Float64
    legend::Vector{LegendSection}
end
zorder(::NodePoints) = 5.0
legendsections(l::NodePoints, ::Ctx) = l.legend

"""
    nodepoints!(p; nodes=:internal, color=:fg, marker=:circle, size=5, strokecolor=:white,
                strokewidth=0.8, colormap=:viridis, colorrange=nothing, palette=:default,
                title="", offset=0)

Draw a marker at nodes (`:internal`, `:tips`, `:all` or a list of node
references). `color`, `marker` and `size` may be single values or per-node
values (see [`nodevalues`](@ref)); nodes whose colour value is missing are
skipped. Numeric colours add a colour bar and categories a legend titled
`title`. Markers: $(join(MARKERS, ", ")).
"""
function nodepoints!(p::TreePlot; nodes=:internal, color=nothing, marker=:circle, size=5,
                     strokecolor=:white, strokewidth::Real=0.8, colormap=:viridis, colorrange=nothing,
                     palette=:default, title="", offset::Real=0, legend::Bool=true)
    sel = _selectnodes(p, nodes)
    th = p.opt[:theme]
    if color === nothing
        cols = Union{Nothing,RGBA}[tocolor(th[:fg]) for _ in 1:nnodes(p.tree)]
        leg = nothing
    elseif _iscolorlike(color) && !(color isa Symbol && any(d -> haskey(d, color), p.tree.data))
        cols = Union{Nothing,RGBA}[tocolor(color) for _ in 1:nnodes(p.tree)]
        leg = nothing
    else
        cols, leg = _colorize(nodevalues(p, color); colormap, colorrange, palette, title)
    end
    mk = marker isa Symbol && !(any(d -> haskey(d, marker), p.tree.data)) ? fill(marker, nnodes(p.tree)) :
         nodevalues(p, marker)
    sz = size isa Real ? fill(Float64(size), nnodes(p.tree)) : nodevalues(p, size)
    keep = [i for i in sel if cols[i] !== nothing && mk[i] !== nothing && sz[i] !== nothing]
    if leg !== nothing && !isempty(leg.entries)
        m1 = mk[keep[1]]
        leg = LegendSection(leg.title, [LegendEntry(e.label, :marker, e.color; marker=m1, size=8,
                                                    stroke=strokecolor) for e in leg.entries], nothing)
    end
    push!(p.layers, NodePoints(keep, RGBA[cols[i] for i in keep], Symbol[Symbol(mk[i]) for i in keep],
                               Float64[sz[i] for i in keep], tocolor(strokecolor), Float64(strokewidth),
                               Float64(offset), legend && leg !== nothing ? [leg] : LegendSection[]))
    return p
end

"""
    tippoints!(p; color=:fg, marker=:circle, size=6, kwargs...)

Markers at the tips, as [`nodepoints!`](@ref) with `nodes = :tips`. The tip
labels move outwards to make room.
"""
function tippoints!(p::TreePlot; size=6, offset=nothing, kwargs...)
    s = size isa Real ? Float64(size) : 8.0
    off = offset === nothing ? s / 2 + 3 : Float64(offset)
    nodepoints!(p; nodes=:tips, size, offset=off, kwargs...)
    for l in p.layers
        l isa TipLabels && (l.offset = max(l.offset, off + s / 2 + 3))
    end
    return p
end

function draw!(c::Canvas, l::NodePoints, ctx::Ctx)
    p = ctx.p
    group(c, "points") do
        for (k, i) in enumerate(l.nodes)
            x, y = xy(ctx.coord, ctx.r[i] + l.offset, p.pos[i])
            marker!(c, x, y, l.markers[k], l.sizes[k]; fill=l.colors[k], stroke=l.stroke, linewidth=l.strokewidth)
        end
    end
end

const SUPPORT_COLORS = ["#1a9850", "#91cf60", "#fee08b", "#d73027"]

"""
    support!(p; key=:support, breaks=auto, colors=green→red, marker=:circle, size=5,
             labels=auto, title="Support", hidebelow=nothing, kwargs...)

Mark internal nodes by support value (bootstrap, posterior, …) read from the
node annotation `key` (or given as per-node values). Values are binned by
`breaks` (default `[70, 90, 95]`, or `[0.7, 0.9, 0.95]` for values in 0–1)
and each bin gets a colour from `colors` (highest first) and a legend entry.
Nodes below `hidebelow` are not marked.
"""
function support!(p::TreePlot; key=:support, breaks=nothing, colors=SUPPORT_COLORS, marker=:circle, size=5,
                  labels=nothing, title="Support", hidebelow=nothing, strokecolor=:white, kwargs...)
    vals = nodevalues(p, key)
    present = [v for v in vals if v isa Real]
    isempty(present) && (@warn "no support values found for $(repr(key))"; return p)
    if breaks === nothing
        breaks = maximum(present) <= 1 ? [0.7, 0.9, 0.95] : [70, 90, 95]
    end
    br = sort(Float64.(collect(breaks)); rev=true)        # high to low
    nb = length(br) + 1
    cols = palette(collect(colors), nb)
    fmt(x) = isinteger(x) ? string(Int(x)) : string(x)
    if labels === nothing
        labels = String[]
        push!(labels, "≥ " * fmt(br[1]))
        for k in 2:length(br)
            push!(labels, fmt(br[k]) * "–" * fmt(br[k-1]))
        end
        push!(labels, "< " * fmt(br[end]))
    end
    cat(v) = (k = findfirst(b -> v >= b, br); k === nothing ? nb : k)
    colorvals = Vector{Any}(nothing, length(vals))
    t = p.tree
    for i in 1:length(vals)
        v = vals[i]
        (v isa Real && !isleaf(t, i) && !isnan(v)) || continue
        hidebelow !== nothing && v < hidebelow && continue
        colorvals[i] = cols[cat(v)]
    end
    nodepoints!(p; nodes=:internal, color=colorvals, marker, size, strokecolor, legend=false, kwargs...)
    used = Set(cat(v) for v in present)
    hidebelow === nothing || (used = Set(cat(v) for v in present if v >= hidebelow))
    entries = [LegendEntry(labels[k], :marker, cols[k]; marker, size=8, stroke=strokecolor)
               for k in 1:nb if k in used]
    push!(p.legends, LegendSection(String(title), entries))
    return p
end

# =========================================================================================
# node labels (text)
# =========================================================================================

struct NodeLabels <: Layer
    nodes::Vector{Int}
    text::Vector{String}
    fontsize::Float64
    color::RGBA
    position::Symbol
    bold::Bool
    halo::Bool
    hideoverlaps::Bool
end
zorder(::NodeLabels) = 6.5

"""
    nodelabels!(p; text=:support, nodes=:internal, fontsize=auto, color=:muted,
                position=:branch, digits=2, bold=false, halo=true)

Write text at nodes: an annotation key (default the support values), node
labels (`text = :label`), or per-node values. `position = :branch` puts it
above the branch just before the node (the usual place for support values);
`:node` puts it just after the node. A label that would overlap something
else moves to the other place (or below the branch); text too long for its
branch always goes after the node. With `hideoverlaps = true`, labels that
fit nowhere are left out instead of drawn over other things.
"""
function nodelabels!(p::TreePlot; text=:support, nodes=:internal, fontsize=nothing, color=nothing,
                     position::Symbol=:branch, digits::Integer=2, bold::Bool=false, halo::Bool=true,
                     hideoverlaps::Bool=false)
    t = p.tree
    vals = text === :label ? Any[isempty(s) ? nothing : s for s in t.label] : nodevalues(p, text)
    sel = _selectnodes(p, nodes)
    fmt(v) = v isa AbstractFloat ? (isinteger(v) ? string(Int(v)) : string(round(v; digits))) : string(v)
    keep = [i for i in sel if vals[i] !== nothing && i != t.root]
    fs = fontsize === nothing ? NaN : Float64(fontsize)
    col = color === nothing ? tocolor(p.opt[:theme][:muted]) : tocolor(color)
    push!(p.layers, NodeLabels(keep, [fmt(vals[i]) for i in keep], fs, col, position, bold, halo, hideoverlaps))
    return p
end

function draw!(c::Canvas, l::NodeLabels, ctx::Ctx)
    p = ctx.p
    co = ctx.coord
    fs = isnan(l.fontsize) ? ctx.fs * 0.8 : l.fontsize
    halo = l.halo ? _bgcolor(ctx) : nothing
    group(c, "nodelabels") do
        t = p.tree
        for (k, i) in enumerate(l.nodes)
            s = l.text[k]
            ang, ha = radial_text_params(co, p.pos[i])
            a = deg2rad(ang)
            up = (sin(a), -cos(a))                   # "up" for the rotated text
            spec(x, y, h, v) = (; x, y, text=s, fontsize=fs, angle=ang, halign=h, valign=v, color=l.color,
                                bold=l.bold, halo, halowidth=2.5)
            # on the branch (above, then below it), or just past the node; text too
            # long for its branch would cross the parent's connector, so it skips those
            # (each also a little further out, to clear a marker drawn at the node)
            blen = ctx.r[i] - ctx.r[t.parent[i]]
            bh = ha === :left ? :right : :left
            onbranch = NamedTuple[]
            for gap in (3.0, 7.0)
                textwidth_px(s, fs; bold=l.bold) + gap + 3 <= blen || continue
                bx, by = xy(co, ctx.r[i] - gap, p.pos[i])
                push!(onbranch, spec(bx + 1.2up[1], by + 1.2up[2], bh, :bottom),
                      spec(bx - 1.2up[1], by - 1.2up[2], bh, :top))
            end
            atnode = NamedTuple[]
            for gap in (4.0, 8.0)
                nx, ny = xy(co, ctx.r[i] + gap, p.pos[i])
                push!(atnode, spec(nx, ny, ha, :center))
            end
            cands = l.position === :branch ? vcat(onbranch, atnode) : vcat(atnode, onbranch)
            softtext!(c, cands; required=!l.hideoverlaps, priority=0)
        end
    end
end

# =========================================================================================
# pie charts at nodes
# =========================================================================================

struct NodePies <: Layer
    nodes::Vector{Int}
    values::Vector{Vector{Float64}}
    colors::Vector{RGBA}
    radius::Vector{Float64}
    stroke::RGBA
    strokewidth::Float64
    legend::Vector{LegendSection}
end
zorder(::NodePies) = 6.0
legendsections(l::NodePies, ::Ctx) = l.legend

"""
    nodepies!(p, data; colors=palette, labels=nothing, radius=7, title="",
              stroke=:white, strokewidth=0.75)

Pie charts at nodes, e.g. ancestral state probabilities. `data` is a
dictionary `node => values`, an annotation key holding vectors, or a matrix
with one row per node of `nodes` (keyword). `labels` names the categories
for the legend. `radius` may be a number or per-node values.
"""
function nodepies!(p::TreePlot, data; nodes=nothing, colors=nothing, labels=nothing, radius=7,
                   title="", stroke=:white, strokewidth::Real=0.75, palette=:default)
    t = p.tree
    if data isa AbstractMatrix
        nodes === nothing && throw(ArgumentError("give `nodes` (one per row of the matrix)"))
        vals = Vector{Any}(nothing, nnodes(t))
        for (k, nd) in enumerate(nodes)
            vals[nodeindex(t, nd)] = Float64.(data[k, :])
        end
    else
        vals = nodevalues(p, data)
    end
    keep = [i for i in preorder(t) if vals[i] isa Union{AbstractVector,Tuple} && sum(vals[i]) > 0]
    isempty(keep) && (@warn "no pie data"; return p)
    k = maximum(length(vals[i]) for i in keep)
    cols = colors === nothing ? PlotPhyloTree.palette(palette, k) : PlotPhyloTree.palette(collect(colors), k)
    rad = radius isa Real ? fill(Float64(radius), nnodes(t)) : nodevalues(p, radius)
    legs = labels === nothing ? LegendSection[] :
           [LegendSection(String(title), [LegendEntry(string(labels[j]), :patch, cols[j]) for j in 1:k])]
    push!(p.layers, NodePies(keep, [Float64.(collect(vals[i])) for i in keep], cols,
                             [Float64(something(rad[i], 7.0)) for i in keep], tocolor(stroke),
                             Float64(strokewidth), legs))
    return p
end

function draw!(c::Canvas, l::NodePies, ctx::Ctx)
    p = ctx.p
    group(c, "pies") do
        for (k, i) in enumerate(l.nodes)
            x, y = xy(ctx.coord, ctx.r[i], p.pos[i])
            pie!(c, x, y, l.radius[k], l.values[k], l.colors; stroke=l.stroke, linewidth=l.strokewidth)
        end
    end
end

# =========================================================================================
# node bars (age intervals, e.g. 95% HPD from BEAST)
# =========================================================================================

struct NodeBars <: Layer
    nodes::Vector{Int}
    intervals::Vector{Tuple{Float64,Float64}}
    color::RGBA
    width::Float64
end
zorder(::NodeBars) = 3.5

"""
    nodebars!(p; key=Symbol("height_95%_HPD"), color=(:steelblue, 0.45), width=5, nodes=:internal)

Bars across nodes showing an interval of node ages (time before the tips),
such as the 95% HPD of node heights in BEAST trees. `key` may also be
per-node `(lo, hi)` values.
"""
function nodebars!(p::TreePlot; key=Symbol("height_95%_HPD"), color=("#4E79A7", 0.45), width::Real=5,
                   nodes=:internal)
    vals = nodevalues(p, key)
    sel = _selectnodes(p, nodes)
    keep = [i for i in sel if vals[i] !== nothing && length(vals[i]) == 2]
    isempty(keep) && (@warn "no intervals found for $(repr(key))"; return p)
    push!(p.layers, NodeBars(keep, [(Float64(vals[i][1]), Float64(vals[i][2])) for i in keep], tocolor(color),
                             Float64(width)))
    return p
end

function draw!(c::Canvas, l::NodeBars, ctx::Ctx)
    p = ctx.p
    H = maximum(p.x)
    group(c, "nodebars") do
        pb = PathBuilder()
        for (k, i) in enumerate(l.nodes)
            lo, hi = l.intervals[k]
            ra = ctx.r0 + (H - hi) * ctx.scale
            rb = ctx.r0 + (H - lo) * ctx.scale
            move!(pb, ctx.coord, ra, p.pos[i])
            line!(pb, ctx.coord, rb, p.pos[i])
        end
        path!(c, pb; stroke=l.color, linewidth=l.width, cap="butt")
    end
end
