# Time scales and data rings outside the tips.

function niceticks(lo::Real, hi::Real; n::Integer=5)
    hi <= lo && return [Float64(lo)]
    span = hi - lo
    raw = span / n
    mag = 10.0^floor(log10(raw))
    step = mag
    for m in (1.0, 2.0, 2.5, 5.0, 10.0)
        step = m * mag
        span / step <= n + 0.5 && break
    end
    first_ = ceil(lo / step - 1e-9) * step
    return [round(v; digits=10) for v in first_:step:(hi+1e-9*span)]
end

_fmttick(v) = (r = round(v; sigdigits=6); isinteger(r) ? string(Int(r)) : string(r))

# =========================================================================================
# time scale
# =========================================================================================

const GEO_EPOCHS = [
    ("Holocene", "H", 0.0, 0.0117, "#FEEBD2"), ("Pleistocene", "Ple", 0.0117, 2.58, "#FFF2AE"),
    ("Pliocene", "Pli", 2.58, 5.333, "#FFFF99"), ("Miocene", "Mio", 5.333, 23.03, "#FFFF00"),
    ("Oligocene", "Oli", 23.03, 33.9, "#FEC07A"), ("Eocene", "Eoc", 33.9, 56.0, "#FDB46C"),
    ("Paleocene", "Pal", 56.0, 66.0, "#FDA75F"), ("Late Cretaceous", "K2", 66.0, 100.5, "#A6D84A"),
    ("Early Cretaceous", "K1", 100.5, 145.0, "#8CCD57"), ("Late Jurassic", "J3", 145.0, 161.5, "#B3E3EE"),
    ("Middle Jurassic", "J2", 161.5, 174.7, "#80CFD8"), ("Early Jurassic", "J1", 174.7, 201.4, "#42AED0"),
    ("Late Triassic", "T3", 201.4, 237.0, "#BD8CC3"), ("Middle Triassic", "T2", 237.0, 247.2, "#B168B1"),
    ("Early Triassic", "T1", 247.2, 251.9, "#983999"),
]
const GEO_PERIODS = [
    ("Quaternary", "Q", 0.0, 2.58, "#F9F97F"), ("Neogene", "N", 2.58, 23.03, "#FFE619"),
    ("Paleogene", "Pg", 23.03, 66.0, "#FD9A52"), ("Cretaceous", "K", 66.0, 145.0, "#7FC64E"),
    ("Jurassic", "J", 145.0, 201.4, "#34B2C9"), ("Triassic", "T", 201.4, 251.9, "#812B92"),
    ("Permian", "P", 251.9, 298.9, "#F04028"), ("Carboniferous", "C", 298.9, 358.9, "#67A599"),
    ("Devonian", "D", 358.9, 419.2, "#CB8C37"), ("Silurian", "S", 419.2, 443.8, "#B3E1B6"),
    ("Ordovician", "O", 443.8, 485.4, "#009270"), ("Cambrian", "Ꞓ", 485.4, 538.8, "#7FA056"),
]
const GEO_ERAS = [
    ("Cenozoic", "Cz", 0.0, 66.0, "#F2F91D"), ("Mesozoic", "Mz", 66.0, 251.9, "#67C5CA"),
    ("Paleozoic", "Pz", 251.9, 538.8, "#99C08D"),
]

struct TimeScale <: Layer
    ticks::Union{Nothing,Vector{Float64}}
    title::String
    rings::Bool
    bands::Bool
    labels::Bool
    axis::Bool
    geo::Union{Nothing,Vector}
    geoalpha::Float64
    origin::Float64
    color::Union{Nothing,RGBA}
    bandcolor::Union{Nothing,RGBA}
    fontsize::Float64
    to::Symbol
end
zorder(::TimeScale) = 0.0

"""
    timescale!(p; ticks=auto, title="", rings=true, bands=true, labels=true, axis=true,
               geo=nothing, geoalpha=0.35, origin=0, color=nothing, bandcolor=nothing,
               fontsize=auto, to=:tips)

A time axis for a dated (ultrametric) tree, measured back from the tips,
which are at age `origin`. Circular layouts get concentric rings and an axis
along the opening; rectangular ones get vertical grid lines and an axis
below the tree. `bands = true` shades every other interval.

`geo = :epochs`, `:periods` or `:eras` colours the background by the
geological time scale (ICS colours; ages in Ma), or pass a vector of
`(name, abbreviation, from, to, colour)` tuples. `to = :labels` or `:all`
carries the rings past the tip labels.
"""
function timescale!(p::TreePlot; ticks=nothing, title::AbstractString="", rings::Bool=true, bands::Bool=true,
                    labels::Bool=true, axis::Bool=true, geo=nothing, geoalpha::Real=0.35, origin::Real=0,
                    color=nothing, bandcolor=nothing, fontsize=nothing, to::Symbol=:tips)
    g = geo === nothing ? nothing : geo === :epochs ? GEO_EPOCHS : geo === :periods ? GEO_PERIODS :
        geo === :eras ? GEO_ERAS : geo isa AbstractVector ? collect(geo) :
        throw(ArgumentError("geo must be :epochs, :periods, :eras or a vector of intervals"))
    push!(p.layers, TimeScale(ticks === nothing ? nothing : Float64.(collect(ticks)), String(title), rings,
                              bands && g === nothing, labels, axis, g, Float64(geoalpha), Float64(origin),
                              color === nothing ? nothing : tocolor(color),
                              bandcolor === nothing ? nothing : tocolor(bandcolor),
                              fontsize === nothing ? NaN : Float64(fontsize), to))
    return p
end

function draw!(c::Canvas, l::TimeScale, ctx::Ctx)
    p = ctx.p
    co = ctx.coord
    H = maximum(p.x)
    H > 0 || return
    n = ntips(p.tree)
    fs = isnan(l.fontsize) ? ctx.fs * 0.85 : l.fontsize
    rage(a) = ctx.r0 + (H - (a - l.origin)) * ctx.scale
    tk = l.ticks === nothing ? niceticks(l.origin, l.origin + H; n=6) : l.ticks
    tk = [v for v in tk if l.origin - 1e-9 <= v <= l.origin + H + 1e-9]
    grid = l.color === nothing ? tocolor(ctx.th[:grid]) : l.color
    bandc = l.bandcolor === nothing ? tocolor(ctx.th[:band]) : l.bandcolor
    muted = tocolor(ctx.th[:muted])
    rmax = l.to === :tips ? ctx.R : l.to === :labels ? ctx.textend : ctx.outer
    full = co isa Polar && co.slot * n > 2π - 1e-6
    p1, p2 = 0.5, n + 0.5
    if co isa Polar
        gapc = full ? 0.5 : 0.5 - (2π - co.slot * n) / 2 / co.slot
    else
        gapc = n + 0.5
    end
    group(c, "timescale") do
        # background: geological intervals or alternating bands
        if l.geo !== nothing
            for (name, abbr, a, b, col) in l.geo
                a >= l.origin + H && continue
                b <= l.origin && continue
                ra = rage(min(b, l.origin + H)); rb = b > l.origin ? rage(max(a, l.origin)) : rage(a)
                rb = min(rb, rmax)
                ra < rb || continue
                pb = PathBuilder()
                region!(pb, co, ra, rb, p1, p2)
                path!(c, pb; fill=withalpha(col, l.geoalpha))
            end
        elseif l.bands && length(tk) >= 2
            edges = sort(tk)
            last(edges) < l.origin + H && push!(edges, l.origin + H)
            for k in 1:length(edges)-1
                iseven(k) || continue
                ra = rage(edges[k+1]); rb = min(rage(edges[k]), rmax)
                ra < rb || continue
                pb = PathBuilder()
                region!(pb, co, ra, rb, p1, p2)
                path!(c, pb; fill=bandc)
            end
        end
        if l.rings
            pb = PathBuilder()
            for v in tk
                r = rage(v)
                r <= rmax + 1e-6 || continue
                move!(pb, co, r, p1)
                across!(pb, co, r, p1, p2)
            end
            path!(c, pb; stroke=grid, linewidth=0.7, dash=:dash)
        end
        if l.axis || l.labels
            _timeaxis!(c, ctx, l, tk, rage, gapc, fs, muted)
        end
    end
end

function _timeaxis!(c, ctx, l::TimeScale, tk, rage, gapc, fs, muted)
    co = ctx.coord
    polar = co isa Polar
    # a wide opening (a fan) puts the axis along the edge of the first tip, facing
    # into the opening; a narrow one puts it along the middle of the opening
    edge = polar && 2π - co.slot * ntips(ctx.p.tree) > deg2rad(40)
    edge && (gapc = 0.5)
    ang, _ = radial_text_params(co, gapc)
    a = deg2rad(ang)
    down = edge ? .-acrossvec(co, gapc) : (-sin(a), cos(a))   # the side the tick labels go on
    # rectangular axes sit below the tips; edge axes leave room for interval names
    shift = !polar ? 8.0 : edge ? -(l.geo === nothing ? 8.0 : 8.0 + fs * 1.3) : 0.0
    ax = (r) -> (xy(co, r, gapc) .+ shift .* acrossvec(co, gapc))
    rs = [rage(v) for v in tk]
    rlo = min(ctx.r0, minimum(rs)); rhi = max(ctx.R, maximum(rs))
    if l.axis
        pb = PathBuilder()
        M!(pb, ax(rlo)...); L!(pb, ax(rhi)...)
        for r in rs
            x, y = ax(r)
            M!(pb, x, y); L!(pb, x + 3.5down[1], y + 3.5down[2])
        end
        path!(c, pb; stroke=muted, linewidth=0.8, cap="butt")
    end
    vertical = !polar && co.dir in (:down, :up)
    if l.labels && vertical
        # an upright axis: horizontal tick labels beside it, the title turned along it
        v = acrossvec(co, gapc)
        wmax = maximum(textwidth_px(_fmttick(t), fs) for t in tk)
        for (t, r) in zip(tk, rs)
            x, y = ax(r)
            text!(c, x + 6v[1], y + 6v[2], _fmttick(t); fontsize=fs, halign=:left, color=muted)
        end
        if !isempty(l.title)
            x, y = ax((rlo + rhi) / 2)
            off = 10 + wmax + fs * 0.6
            text!(c, x + off * v[1], y + off * v[2], l.title; fontsize=fs, angle=-90, halign=:center, color=muted)
        end
    elseif l.labels
        for (v, r) in zip(tk, rs)
            x, y = ax(r)
            text!(c, x + (5 + fs * 0.5) * down[1], y + (5 + fs * 0.5) * down[2], _fmttick(v); fontsize=fs,
                  angle=ang, halign=:center, color=muted)
        end
        if !isempty(l.title)
            x, y = ax((rlo + rhi) / 2)
            off = 7 + fs * 1.6
            text!(c, x + off * down[1], y + off * down[2], l.title; fontsize=fs, angle=ang, halign=:center,
                  color=muted)
        end
    end
    if l.geo !== nothing
        # interval names on the other side of the axis (or above a rectangular tree)
        H = maximum(ctx.p.x)
        for (name, abbr, a0, b0, col) in l.geo
            lo = max(a0, l.origin); hi = min(b0, l.origin + H)
            lo < hi || continue
            r1 = rage(hi); r2 = rage(lo)
            w = r2 - r1
            s = textwidth_px(name, fs * 0.85) < w - 4 ? name : textwidth_px(abbr, fs * 0.85) < w - 2 ? abbr : ""
            isempty(s) && continue
            if polar
                x, y = ax((r1 + r2) / 2)
                text!(c, x - (4 + fs * 0.45) * down[1], y - (4 + fs * 0.45) * down[2], s; fontsize=fs * 0.85,
                      angle=ang, halign=:center, color=darken(col, 0.45))
            else
                x, y = xy(co, (r1 + r2) / 2, 0.5)
                v = acrossvec(co, 0.5)
                text!(c, x - (fs * 0.9) * v[1], y - (fs * 0.9) * v[2], s; fontsize=fs * 0.85, angle=ang,
                      halign=:center, color=darken(col, 0.45))
            end
        end
    end
end

"""
    scalebar!(p; length=auto, label=auto, position=:bottomleft, linewidth=1.5)

A scale bar for branch lengths, drawn under the tree.
"""
function scalebar!(p::TreePlot; length=nothing, label=nothing, position::Symbol=:bottomleft,
                   linewidth::Real=1.5)
    p.opt[:scalebar] = (; length, label, position, linewidth=Float64(linewidth))
    return p
end

function _drawscalebar!(c::Canvas, ctx::Ctx)
    sb = ctx.p.opt[:scalebar]
    sb === nothing && return
    H = maximum(ctx.p.x)
    (H > 0 && ctx.scale > 0) || return
    L = sb.length === nothing ? niceticks(0, H / 4; n=1)[end] : Float64(sb.length)
    L == 0 && (L = niceticks(0, H / 4; n=2)[2])
    w = L * ctx.scale
    b = c.bbox
    fs = ctx.fs * 0.85
    x0 = sb.position in (:bottomright, :topright) ? b.xmax - w : b.xmin
    y0 = sb.position in (:topleft, :topright) ? b.ymin - fs - 10 : b.ymax + 12
    col = tocolor(ctx.th[:fg])
    pb = PathBuilder()
    M!(pb, x0, y0 - 3); L!(pb, x0, y0); L!(pb, x0 + w, y0); L!(pb, x0 + w, y0 - 3)
    path!(c, pb; stroke=col, linewidth=sb.linewidth, cap="butt", join="miter")
    lab = sb.label === nothing ? _fmttick(L) : string(sb.label)
    text!(c, x0 + w / 2, y0 + 3, lab; fontsize=fs, halign=:center, valign=:top, color=col)
end

# =========================================================================================
# heatmap ring
# =========================================================================================

struct TipHeatmap <: Layer
    names::Vector{String}
    cells::Matrix{Union{Nothing,RGBA}}     # nnodes × ncol
    cellwidth::Float64
    gap::Float64
    colnames::Bool
    border::Union{Nothing,RGBA}
    legend::Vector{LegendSection}
    offset::Float64
    key::Int
end

bandkey(l::TipHeatmap) = (:heatmap, l.key)
bandgap(l::TipHeatmap) = l.offset
zorder(::TipHeatmap) = 6.8
legendsections(l::TipHeatmap, ::Ctx) = l.legend
bandwidth(l::TipHeatmap, ::Ctx, start) = size(l.cells, 2) * (l.cellwidth + l.gap) - l.gap

"""
    tipheatmap!(p, data; columns=nothing, colormap=:viridis, colorrange=nothing,
                palette=:default, cellwidth=12, gap=1.5, colnames=true, title="",
                border=:background, offset=6)

A ring (circular) or block (rectangular) of coloured cells beside the tips.
`data` can be

- a dictionary `tip => value` (one column) or `tip => vector` (several columns),
- a matrix with one row per tip, with `rows = tip labels` (default: the tips
  in drawing order),
- a vector of per-tip values, or
- a `NamedTuple` of any of the one-column forms, giving named columns that
  are coloured independently (e.g. a numeric trait and a category).

Numbers are coloured by `colormap`, anything else by `palette`; each adds a
legend titled `title` (or the column name).
"""
function tipheatmap!(p::TreePlot, data; rows=nothing, columns=nothing, colormap=:viridis, colorrange=nothing,
                     palette=:default, cellwidth::Real=12, gap::Real=1.5, colnames::Bool=true, title="",
                     border=:background, offset::Real=6)
    t = p.tree
    nn = nnodes(t)
    groups = Vector{Tuple{String,Vector{Vector{Any}}}}()   # (legend title, columns)
    names = String[]
    if data isa NamedTuple
        for (k, v) in pairs(data)
            col = nodevalues(p, v)
            push!(groups, (string(k), [col]))
            push!(names, string(k))
        end
    elseif data isa AbstractMatrix
        rn = rows === nothing ? tipnames(t) : rows
        size(data, 1) == length(rn) || throw(ArgumentError("matrix needs one row per tip label"))
        cols = Vector{Vector{Any}}()
        for j in 1:size(data, 2)
            col = Vector{Any}(nothing, nn)
            for (k, r) in enumerate(rn)
                col[nodeindex(t, r)] = data[k, j]
            end
            push!(cols, col)
        end
        push!(groups, (String(title), cols))
        append!(names, columns === nothing ? ["" for _ in 1:size(data, 2)] : string.(columns))
    else
        v = nodevalues(p, data)
        m = maximum((x isa Union{AbstractVector,Tuple} ? length(x) : 1 for x in v if x !== nothing); init=1)
        if any(x -> x isa Union{AbstractVector,Tuple}, v)
            cols = [Any[x === nothing ? nothing : x[j] for x in v] for j in 1:m]
        else
            cols = [v]
        end
        push!(groups, (String(title), cols))
        append!(names, columns === nothing ? ["" for _ in 1:length(cols)] : string.(columns))
    end
    ncol = sum(length(g[2]) for g in groups)
    cells = Matrix{Union{Nothing,RGBA}}(nothing, nn, ncol)
    legs = LegendSection[]
    j = 0
    for (gt, cols) in groups
        allv = reduce(vcat, cols)
        cc, leg = _colorize(allv; colormap, colorrange, palette, title=gt)
        for (k, _) in enumerate(cols)
            j += 1
            cells[:, j] = cc[(k-1)*nn+1:k*nn]
        end
        leg === nothing || push!(legs, leg)
    end
    bd = border === :background ? nothing : border === nothing ? TRANSPARENT : tocolor(border)
    key = count(l -> l isa TipHeatmap, p.layers) + 1
    push!(p.layers, TipHeatmap(names, cells, Float64(cellwidth), Float64(gap), colnames, bd, legs,
                               Float64(offset), key))
    return p
end

function draw!(c::Canvas, l::TipHeatmap, ctx::Ctx)
    p = ctx.p
    co = ctx.coord
    start = band(ctx, l)[1]
    border = l.border === nothing ? _bgcolor(ctx) : l.border
    n = ntips(p.tree)
    group(c, "heatmap") do
        for j in 1:size(l.cells, 2)
            r1 = start + (j - 1) * (l.cellwidth + l.gap)
            r2 = r1 + l.cellwidth
            for i in tips(p.tree)
                col = l.cells[i, j]
                col === nothing && continue
                pb = PathBuilder()
                region!(pb, co, r1, r2, p.pos[i] - 0.5, p.pos[i] + 0.5)
                path!(c, pb; fill=col, stroke=border, linewidth=0.4, join="miter")
            end
            if l.colnames && !isempty(l.names[j])
                fs = ctx.fs * 0.8
                if co isa Polar
                    full = co.slot * n > 2π - 1e-6
                    pg = full ? 0.5 : 0.5 - 0.25
                    x, y = xy(co, (r1 + r2) / 2, pg)
                    ang, ha = radial_text_params(co, pg)
                    v = acrossvec(co, pg)
                    text!(c, x - 3v[1], y - 3v[2], l.names[j]; fontsize=fs, angle=ang - 90,
                          halign=:left, color=ctx.th[:muted])
                else
                    x, y = xy(co, (r1 + r2) / 2, 0.5)
                    v = acrossvec(co, 0.5)
                    ang = co.dir in (:right, :left) ? -90.0 : 0.0
                    text!(c, x - 4v[1], y - 4v[2], l.names[j]; fontsize=fs, angle=ang, halign=:left,
                          color=ctx.th[:muted])
                end
            end
        end
    end
end

# =========================================================================================
# bar ring
# =========================================================================================

struct TipBars <: Layer
    values::Vector{Union{Nothing,Float64}}
    colors::Vector{Union{Nothing,RGBA}}
    length::Float64
    width::Float64
    lim::Float64
    offset::Float64
    legend::Vector{LegendSection}
    key::Int
    title::String
end
bandkey(l::TipBars) = (:tipbars, l.key)
bandgap(l::TipBars) = l.offset
bandwidth(l::TipBars, ::Ctx, start) = l.length
zorder(::TipBars) = 6.8
legendsections(l::TipBars, ::Ctx) = l.legend

"""
    tipbars!(p, values; color=1, length=60, width=0.7, limit=auto, offset=6, title="",
             colormap=:viridis, palette=:default)

A bar chart of per-tip numbers beside the tips. `color` is a colour or
per-tip values (coloured as in [`nodepoints!`](@ref)). Bars are scaled so
`limit` (default: the largest value) spans `length` px; `width` is the
fraction of the tip spacing each bar fills.
"""
function tipbars!(p::TreePlot, values; color=1, length::Real=60, width::Real=0.7, limit=nothing,
                  offset::Real=6, title::AbstractString="", colormap=:viridis, palette=:default)
    v = nodevalues(p, values)
    vals = Union{Nothing,Float64}[x isa Real ? Float64(x) : nothing for x in v]
    nums = [x for x in vals if x !== nothing]
    isempty(nums) && throw(ArgumentError("no numeric values"))
    lim = limit === nothing ? maximum(abs, nums) : Float64(limit)
    legs = LegendSection[]
    if _iscolorlike(color) && !(color isa Symbol && any(d -> haskey(d, color), p.tree.data))
        cols = Union{Nothing,RGBA}[tocolor(color) for _ in vals]
    else
        cols, leg = _colorize(nodevalues(p, color); colormap, palette)
        leg === nothing || push!(legs, leg)
    end
    key = count(l -> l isa TipBars, p.layers) + 1
    push!(p.layers, TipBars(vals, cols, Float64(length), Float64(width), lim, Float64(offset), legs, key,
                            String(title)))
    return p
end

function draw!(c::Canvas, l::TipBars, ctx::Ctx)
    p = ctx.p
    co = ctx.coord
    start = band(ctx, l)[1]
    h = l.width / 2
    group(c, "tipbars") do
        for i in tips(p.tree)
            v = l.values[i]
            (v === nothing || l.colors[i] === nothing || l.lim <= 0) && continue
            len = clamp(v / l.lim, 0, 1) * l.length
            len > 0 || continue
            pb = PathBuilder()
            region!(pb, co, start, start + len, p.pos[i] - h, p.pos[i] + h)
            path!(c, pb; fill=l.colors[i])
        end
        # baseline
        pb = PathBuilder()
        n = ntips(p.tree)
        move!(pb, co, start, 0.5)
        across!(pb, co, start, 0.5, n + 0.5)
        path!(c, pb; stroke=ctx.th[:muted], linewidth=0.6)
        if !isempty(l.title)
            pg = co isa Polar ? 0.5 - 0.25 : 0.5
            x, y = xy(co, start + l.length / 2, pg)
            v = acrossvec(co, pg)
            ang, _ = radial_text_params(co, pg)
            text!(c, x - 4v[1], y - 4v[2], l.title; fontsize=ctx.fs * 0.8, angle=ang, halign=:center,
                  valign=:bottom, color=ctx.th[:muted])
        end
    end
end

# =========================================================================================
# images
# =========================================================================================

struct TipImages <: Layer
    nodes::Vector{Int}
    hrefs::Vector{String}         # a URL/data URI, or SVG markup (drawn inline)
    aspect::Vector{Float64}       # width / height
    size::Float64
    offset::Float64
    key::Int
end
bandkey(l::TipImages) = (:images, l.key)
bandgap(l::TipImages) = l.offset
bandwidth(l::TipImages, ::Ctx, start) = l.size
zorder(::TipImages) = 8.0

"""
    tipimages!(p, images; size=40, offset=8)

Images beside tips or clades. `images` maps node references (a tip label,
or a collection of tip labels meaning their clade, centred on it) to an
image: a file path (PNG, JPEG, GIF, WebP or SVG), an SVG string, a data URI
or a URL. Each image is fitted in a `size` × `size` px box.
"""
function tipimages!(p::TreePlot, images; size::Real=40, offset::Real=8)
    nodes = Int[]; hrefs = String[]; asp = Float64[]
    for (k, src) in (images isa AbstractDict ? images : pairs(images))
        push!(nodes, nodeindex(p.tree, k))
        href, a = _imagehref(src)
        push!(hrefs, href); push!(asp, a)
    end
    key = count(l -> l isa TipImages, p.layers) + 1
    push!(p.layers, TipImages(nodes, hrefs, asp, Float64(size), Float64(offset), key))
    return p
end

function draw!(c::Canvas, l::TipImages, ctx::Ctx)
    p = ctx.p
    start = band(ctx, l)[1]
    s = l.size
    group(c, "images") do
        for (k, i) in enumerate(l.nodes)
            a, b = _posrange(p, i)
            x, y = xy(ctx.coord, start + s / 2, (a + b) / 2)
            w, h = l.aspect[k] >= 1 ? (s, s / l.aspect[k]) : (s * l.aspect[k], s)
            src = l.hrefs[k]
            if startswith(src, "<")
                svgimage!(c, x - w / 2, y - h / 2, w, h, src)
            else
                image!(c, x - w / 2, y - h / 2, w, h, src)
            end
        end
    end
end

const _MIME = Dict(".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".gif" => "image/gif",
                   ".webp" => "image/webp", ".svg" => "image/svg+xml")

function _imagehref(src::AbstractString)
    s = String(src)
    if startswith(s, "data:")
        return s, 1.0
    elseif startswith(lstrip(s), "<")
        # SVG markup is drawn inline (as a nested <svg>), which every renderer supports
        occursin("<svg", s) || throw(ArgumentError("image markup does not contain an <svg> element"))
        return String(lstrip(s)), _svgaspect(s)
    elseif startswith(s, "http://") || startswith(s, "https://")
        return s, 1.0
    elseif isfile(s)
        ext = lowercase(splitext(s)[2])
        haskey(_MIME, ext) || throw(ArgumentError("unsupported image type $ext"))
        bytes = read(s)
        a = ext == ".png" ? _pngaspect(bytes) : ext in (".jpg", ".jpeg") ? _jpegaspect(bytes) :
            ext == ".svg" ? _svgaspect(String(copy(bytes))) : 1.0
        ext == ".svg" && return String(lstrip(String(bytes))), a
        return "data:" * _MIME[ext] * ";base64," * base64encode(bytes), a
    end
    throw(ArgumentError("image \"$(first(s, 60))\" is not a file, URL, data URI or SVG string"))
end

function _pngaspect(b::Vector{UInt8})
    length(b) < 24 && return 1.0
    w = (UInt32(b[17]) << 24) | (UInt32(b[18]) << 16) | (UInt32(b[19]) << 8) | b[20]
    h = (UInt32(b[21]) << 24) | (UInt32(b[22]) << 16) | (UInt32(b[23]) << 8) | b[24]
    return h > 0 ? w / h : 1.0
end

function _jpegaspect(b::Vector{UInt8})
    i = 3
    while i + 8 <= length(b)
        b[i] == 0xFF || (i += 1; continue)
        m = b[i+1]
        if m in (0xC0, 0xC1, 0xC2)
            h = (Int(b[i+5]) << 8) | b[i+6]
            w = (Int(b[i+7]) << 8) | b[i+8]
            return h > 0 ? w / h : 1.0
        end
        len = (Int(b[i+2]) << 8) | b[i+3]
        i += 2 + len
    end
    return 1.0
end

function _svgaspect(s::AbstractString)
    m = match(r"viewBox\s*=\s*\"\s*[-\d.e]+[\s,]+[-\d.e]+[\s,]+([\d.e]+)[\s,]+([\d.e]+)"i, s)
    if m !== nothing
        w = parse(Float64, m.captures[1]); h = parse(Float64, m.captures[2])
        return h > 0 ? w / h : 1.0
    end
    mw = match(r"<svg[^>]*\swidth\s*=\s*\"([\d.]+)"i, s)
    mh = match(r"<svg[^>]*\sheight\s*=\s*\"([\d.]+)"i, s)
    (mw === nothing || mh === nothing) && return 1.0
    return parse(Float64, mw.captures[1]) / parse(Float64, mh.captures[1])
end
