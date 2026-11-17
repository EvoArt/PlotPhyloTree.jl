module PlotPhyloTreeMakieExt

# Makie interface: the figure is laid out as for SVG, then its recorded
# primitives are translated into a few Makie plots. Runs of primitives of the
# same kind and style are merged into one plot call (one `poly`, `lines` or
# `text` per run), so drawing order is kept while big trees stay fast.

import Makie
using Makie: (..)
using PlotPhyloTree
using PlotPhyloTree: TreePlot, Scene, Prim, GroupPrim, PathPrim, RectPrim, CirclePrim, TextPrim, ImagePrim, ArcTextPrim,
                     RGBA, Seg, isvisible, scene, foreachprim, _polylines, _dashvec, _arcpoints
using Base64: base64decode
import PlotPhyloTree: phyloplot, phyloplot!, phylofigure

Makie.@recipe PhyloPlot (tree,) begin
    "Multiplies line widths (Makie line widths are in screen px, not data units)."
    linewidthscale = 1.0
    "Multiplies label font sizes (labels are sized in data units)."
    fontscale = 1.0
    "Draw `tipimages!` images (PNG/JPEG data decoded with FileIO; SVG images are skipped)."
    images = true
end

_treeplot(p::TreePlot) = p
_treeplot(t) = treeplot(t)

_c(c::RGBA) = Makie.RGBAf(c.r, c.g, c.b, c.a)
_pt(x, y) = Makie.Point2f(x, -y)

# --- batches ------------------------------------------------------------------------

mutable struct Batch
    kind::Symbol            # :poly, :lines, :text
    key::Any
    polys::Vector{Vector{Makie.Point2f}}
    colors::Vector{Makie.RGBAf}
    points::Vector{Makie.Point2f}
    strings::Vector{String}
    sizes::Vector{Float64}
    rotations::Vector{Float64}
    aligns::Vector{Tuple{Symbol,Symbol}}
end
Batch(kind, key) = Batch(kind, key, Vector{Makie.Point2f}[], Makie.RGBAf[], Makie.Point2f[], String[], Float64[],
                         Float64[], Tuple{Symbol,Symbol}[])

function _flush!(plot, b::Union{Nothing,Batch}, opts)
    b === nothing && return
    if b.kind === :poly
        strokecolor, strokewidth = b.key
        Makie.poly!(plot, b.polys; color=b.colors, strokecolor, strokewidth=strokewidth * opts.lws)
    elseif b.kind === :lines
        lw, dash, cap, join = b.key
        style = isempty(dash) ? nothing : Makie.Linestyle(Float32.(cumsum([0.0; dash]) ./ max(lw, 1e-3)))
        Makie.lines!(plot, b.points; color=b.colors, linewidth=lw * opts.lws, linestyle=style,
                     linecap=cap, joinstyle=join)
    else # :text
        font, halo, halowidth = b.key
        args = (; text=b.strings, fontsize=b.sizes .* opts.fs, rotation=b.rotations, align=b.aligns, font,
                markerspace=:data)
        # the glyph outline is drawn over the fill, so the halo is a separate pass underneath
        halowidth > 0 && Makie.text!(plot, b.points; args..., color=halo, strokecolor=halo,
                                     strokewidth=halowidth * opts.lws)
        Makie.text!(plot, b.points; args..., color=b.colors)
    end
    return
end

# the open batch, or a new one when kind/key change
function _batch!(plot, state, kind, key, opts)
    b = state[]
    if b === nothing || b.kind !== kind || b.key != key
        _flush!(plot, b, opts)
        b = state[] = Batch(kind, key)
    end
    return b
end

_capsym(cap) = cap == "butt" ? :butt : cap == "square" ? :square : :round
_joinsym(j) = j == "miter" ? :miter : j == "bevel" ? :bevel : :round

function _stroke!(plot, state, opts, lines, color::RGBA, lw, dash, cap, join)
    (isvisible(color) && lw > 0) || return
    b = _batch!(plot, state, :lines, (Float64(lw), _dashvec(dash, lw), _capsym(cap), _joinsym(join)), opts)
    c = _c(color)
    for (pts, closed) in lines
        isempty(b.points) || (push!(b.points, Makie.Point2f(NaN, NaN)); push!(b.colors, c))
        for (x, y) in pts
            push!(b.points, _pt(x, y)); push!(b.colors, c)
        end
        closed && (push!(b.points, _pt(pts[1]...)); push!(b.colors, c))
    end
end

function _fill!(plot, state, opts, lines, fill::RGBA, stroke::RGBA, lw)
    sc = isvisible(stroke) && lw > 0 ? (_c(stroke), Float64(lw)) : (Makie.RGBAf(0, 0, 0, 0), 0.0)
    b = _batch!(plot, state, :poly, sc, opts)
    for (pts, _) in lines
        length(pts) >= 3 || continue
        push!(b.polys, [_pt(x, y) for (x, y) in pts]); push!(b.colors, _c(fill))
    end
end

function _draw!(plot, state, opts, p::PathPrim)
    lines = _polylines(p.segs)
    if isvisible(p.fill)
        # a dashed outline cannot go on the polygon: draw it separately
        plain = p.dash === nothing || p.dash === :solid
        _fill!(plot, state, opts, lines, p.fill, plain ? p.stroke : RGBA(0, 0, 0, 0), p.linewidth)
        plain || _stroke!(plot, state, opts, lines, p.stroke, p.linewidth, p.dash, p.cap, p.join)
    else
        _stroke!(plot, state, opts, lines, p.stroke, p.linewidth, p.dash, p.cap, p.join)
    end
end

function _rectpoints(p::RectPrim)
    x, y, w, h = p.x, p.y, p.w, p.h
    r = min(p.rx, w / 2, h / 2)
    r <= 0 && return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    pts = Tuple{Float64,Float64}[]
    for (cx, cy, a) in ((x + w - r, y + r, -π / 2), (x + w - r, y + h - r, 0.0), (x + r, y + h - r, π / 2),
                        (x + r, y + r, π))
        push!(pts, (cx + r * cos(a), cy + r * sin(a)))
        append!(pts, _arcpoints(Seg('A', 0, 0, cx, cy, r, a, a + π / 2)))
    end
    return pts
end

function _draw!(plot, state, opts, p::RectPrim)
    if !isempty(p.gradient)
        _flush!(plot, state[], opts); state[] = nothing
        cols = reshape(_c.(p.gradient), :, 1)
        Makie.image!(plot, p.x .. (p.x + p.w), (-p.y - p.h) .. (-p.y), cols; interpolate=true)
        return
    end
    isvisible(p.fill) || isvisible(p.stroke) || return
    pts = _rectpoints(p)
    if isvisible(p.fill)
        _fill!(plot, state, opts, [(pts, true)], p.fill, p.stroke, p.linewidth)
    else
        _stroke!(plot, state, opts, [(pts, true)], p.stroke, p.linewidth, nothing, "butt", "miter")
    end
end

function _draw!(plot, state, opts, p::CirclePrim)
    n = clamp(ceil(Int, 2π * p.r / 2), 16, 180)
    pts = [(p.x + p.r * cos(2π * k / n), p.y + p.r * sin(2π * k / n)) for k in 0:n-1]
    if isvisible(p.fill)
        _fill!(plot, state, opts, [(pts, true)], p.fill, p.stroke, p.linewidth)
    else
        _stroke!(plot, state, opts, [(pts, true)], p.stroke, p.linewidth, nothing, "round", "round")
    end
end

const _VALIGN = Dict(:center => :center, :baseline => :baseline, :top => :top, :bottom => :bottom)

function _draw!(plot, state, opts, p::TextPrim)
    font = p.bold && p.italic ? :bold_italic : p.bold ? :bold : p.italic ? :italic : :regular
    halo = isvisible(p.halo) ? _c(p.halo) : Makie.RGBAf(0, 0, 0, 0)
    b = _batch!(plot, state, :text, (font, halo, isvisible(p.halo) ? p.halowidth : 0.0), opts)
    push!(b.points, _pt(p.x, p.y)); push!(b.strings, p.text); push!(b.sizes, p.fontsize)
    push!(b.rotations, -deg2rad(p.angle)); push!(b.aligns, (p.halign, _VALIGN[p.valign]))
    push!(b.colors, _c(p.color))
end

_draw!(plot, state, opts, p::ArcTextPrim) = foreach(g -> _draw!(plot, state, opts, g), p.glyphs)

function _loadimage(src::AbstractString)
    m = match(r"^data:image/(png|jpeg|gif)(;base64)?,(.*)$"s, src)
    m === nothing && return nothing
    fmt = m.captures[1] == "png" ? Makie.FileIO.format"PNG" :
          m.captures[1] == "jpeg" ? Makie.FileIO.format"JPEG" : Makie.FileIO.format"GIF"
    bytes = base64decode(m.captures[3])
    return Makie.FileIO.load(Makie.FileIO.Stream{fmt}(IOBuffer(bytes)))
end

function _draw!(plot, state, opts, p::ImagePrim)
    opts.images || return
    img = p.svg ? nothing : try
        _loadimage(p.src)
    catch err
        @warn "could not decode an image for Makie (is ImageIO installed?)" exception = err
        nothing
    end
    if img === nothing
        p.svg && @warn "Makie cannot draw SVG images; skipped" maxlog = 1
        return
    end
    _flush!(plot, state[], opts); state[] = nothing
    Makie.image!(plot, p.x .. (p.x + p.w), (-p.y - p.h) .. (-p.y), rotr90(img))
end

function _drawscene!(plot, sc::Scene; lws=1.0, fs=1.0, images=true)
    opts = (; lws=Float64(lws), fs=Float64(fs), images=Bool(images))
    state = Ref{Union{Nothing,Batch}}(nothing)
    foreachprim(p -> _draw!(plot, state, opts, p), sc.prims)
    _flush!(plot, state[], opts)
    return plot
end

function Makie.plot!(plot::PhyloPlot)
    tp = _treeplot(plot[1][])
    _drawscene!(plot, scene(tp); lws=plot.linewidthscale[], fs=plot.fontscale[], images=plot.images[])
    return plot
end

function phylofigure(obj; scale::Real=1, figure=(;), axis=(;), kwargs...)
    tp = _treeplot(obj)
    sc = scene(tp)
    bg = isvisible(sc.background) ? _c(sc.background) : Makie.RGBAf(1, 1, 1, 0)
    fig = Makie.Figure(; size=(round(Int, scale * sc.width), round(Int, scale * sc.height)),
                       backgroundcolor=bg, figure_padding=0, figure...)
    ax = Makie.Axis(fig[1, 1]; aspect=Makie.DataAspect(), backgroundcolor=bg, axis...)
    Makie.hidedecorations!(ax)
    Makie.hidespines!(ax)
    pl = phyloplot!(ax, tp; linewidthscale=scale, kwargs...)
    Makie.limits!(ax, sc.x0, sc.x0 + sc.width, -(sc.y0 + sc.height), -sc.y0)
    return Makie.FigureAxisPlot(fig, ax, pl)
end

end
