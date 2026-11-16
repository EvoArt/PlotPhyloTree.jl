# Legend and title, placed after everything else is drawn.

"""
    legend!(p, title, entries; kind=:patch, marker=:circle)

Add a legend section by hand. `entries` is a vector of `label => colour`
pairs; `kind` is `:patch`, `:marker` or `:line`.
"""
function legend!(p::TreePlot, title::AbstractString, entries; kind::Symbol=:patch, marker::Symbol=:circle)
    es = [LegendEntry(string(first(e)), kind, last(e); marker, size=8) for e in entries]
    push!(p.legends, LegendSection(String(title), es))
    return p
end

function _legendsections(ctx::Ctx)
    secs = LegendSection[]
    append!(secs, ctx.p.legends)
    for l in ctx.p.layers
        append!(secs, legendsections(l, ctx))
    end
    return filter(s -> !isempty(s.entries) || s.colorbar !== nothing, secs)
end

function _drawlegend!(c::Canvas, ctx::Ctx)
    pos = ctx.p.opt[:legend]
    pos === :none && return
    secs = _legendsections(ctx)
    isempty(secs) && return
    polar = ctx.coord isa Polar
    auto = pos === :auto
    auto && (pos = polar ? :topright : :right)
    fs = clamp(ctx.fs, 9.0, 12.0)
    fg = tocolor(ctx.th[:fg])
    muted = tocolor(ctx.th[:muted])
    rowh = fs * 1.55
    cbw = 120.0
    # measure
    width = 0.0
    gtitle = ctx.p.opt[:legendtitle]
    height = gtitle === nothing ? 0.0 : fs * 1.9
    gtitle === nothing || (width = textwidth_px(string(gtitle), fs * 1.1; bold=true))
    for (k, s) in enumerate(secs)
        k > 1 && (height += fs * 0.9)
        if !isempty(s.title)
            width = max(width, textwidth_px(s.title, fs; bold=true))
            height += rowh
        end
        if s.colorbar !== nothing
            width = max(width, cbw + 10)
            height += 10 + fs * 1.6
        else
            for e in s.entries
                width = max(width, 20 + textwidth_px(e.label, fs))
                height += rowh
            end
        end
    end
    pad = 8.0
    W = width + 2pad; H = height + 2pad - fs * 0.3
    # place
    b = c.bbox
    if pos === :right
        x0 = b.xmax + 18; y0 = polar ? -H / 2 : b.ymin
        polar || (y0 = max(b.ymin, (b.ymin + b.ymax) / 2 - H / 2))
    elseif pos === :left
        x0 = b.xmin - 18 - W; y0 = polar ? -H / 2 : b.ymin
    elseif pos === :bottom
        x0 = (b.xmin + b.xmax) / 2 - W / 2; y0 = b.ymax + 14
    elseif pos === :top
        x0 = (b.xmin + b.xmax) / 2 - W / 2; y0 = b.ymin - 14 - H
    elseif pos in (:topright, :topleft, :bottomright, :bottomleft)
        right = pos in (:topright, :bottomright)
        top = pos in (:topright, :topleft)
        x0 = right ? b.xmax - W : b.xmin
        y0 = top ? b.ymin : b.ymax - H
        free = false
        if auto
            # the first corner of the drawing with nothing under the box (plus a gap)
            cl = collider(c)
            g = 10.0
            for (r, tp) in ((true, true), (false, true), (true, false), (false, false))
                xa = r ? b.xmax - W : b.xmin
                ya = tp ? b.ymin : b.ymax - H
                if !collides(cl, _rectpts(xa - g, ya - g, W + 2g, H + 2g))
                    x0, y0, free = xa, ya, true
                    right, top = r, tp
                    break
                end
            end
        end
        if polar && !free
            # keep the box clear of the circular plot
            Rc = max(-b.xmin, b.xmax, -b.ymin, b.ymax) + 14
            nx = right ? x0 : x0 + W
            ny = top ? y0 + H : y0
            if nx^2 + ny^2 < Rc^2
                need = abs(ny) < Rc ? sqrt(Rc^2 - ny^2) : 0.0
                if right
                    x0 = max(x0, need)
                else
                    x0 = min(x0, -need - W)
                end
            end
        end
    else
        throw(ArgumentError("legend must be :auto, :right, :left, :bottom, :top, :topright, :topleft, " *
                            ":bottomright, :bottomleft or :none"))
    end
    # draw
    group(c, "legend") do
        y = y0 + pad
        x = x0 + pad
        if gtitle !== nothing
            text!(c, x, y + fs * 0.55, string(gtitle); fontsize=fs * 1.1, bold=true, color=fg)
            y += fs * 1.9
        end
        for (k, s) in enumerate(secs)
            k > 1 && (y += fs * 0.9)
            if !isempty(s.title)
                text!(c, x, y + rowh / 2, s.title; fontsize=fs, bold=true, color=fg)
                y += rowh
            end
            if s.colorbar !== nothing
                cm, lo, hi = s.colorbar
                _colorbar!(c, x, y + 2, cbw, 9.0, cm)
                for (v, fx) in ((lo, 0.0), ((lo + hi) / 2, 0.5), (hi, 1.0))
                    text!(c, x + fx * cbw, y + 12 + fs * 0.55, _fmttick(round(v; sigdigits=3)); fontsize=fs * 0.85,
                          halign=fx == 0 ? :left : fx == 1 ? :right : :center, color=muted)
                end
                y += 10 + fs * 1.6
            else
                for e in s.entries
                    cy = y + rowh / 2
                    if e.kind === :marker
                        marker!(c, x + 6, cy, e.marker, min(e.size, 10); fill=e.color, stroke=e.stroke, linewidth=0.8)
                    elseif e.kind === :line
                        line!(c, x, cy, x + 13, cy; color=e.color, linewidth=max(e.size, 2), cap="butt")
                    else
                        rect!(c, x, cy - 5.5, 13, 11; fill=e.color, rx=2)
                    end
                    text!(c, x + 20, cy, e.label; fontsize=fs, color=fg)
                    y += rowh
                end
            end
        end
    end
end

function _colorbar!(c::Canvas, x, y, w, h, cm::Vector{RGBA})
    rect!(c, x, y, w, h; gradient=cm)
end

function _drawtitle!(c::Canvas, ctx::Ctx)
    title = ctx.p.opt[:title]
    sub = ctx.p.opt[:subtitle]
    (title === nothing && sub === nothing) && return
    b = c.bbox
    tfs = clamp(ctx.fs * 1.7, 15.0, 24.0)
    sfs = tfs * 0.62
    y = b.ymin - 12
    x = b.xmin
    if sub !== nothing
        text!(c, x, y, string(sub); fontsize=sfs, valign=:baseline, color=ctx.th[:muted])
        y -= sfs * 1.45
    end
    title === nothing || text!(c, x, y, string(title); fontsize=tfs, valign=:baseline, bold=true, color=ctx.th[:fg])
end
