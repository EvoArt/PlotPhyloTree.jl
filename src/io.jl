# Display, saving and preview.

Base.show(io::IO, ::MIME"image/svg+xml", p::TreePlot) = print(io, render(p))

function Base.show(io::IO, p::TreePlot)
    print(io, "TreePlot(", ntips(p.tree), " tips, ", p.layout, ", ", length(p.layers), " layers)")
end

"""
    svgstring(p) -> String

The figure as an SVG document.
"""
svgstring(p::TreePlot) = render(p)

"""
    savefig(path, p; scale=2) -> path

Write `p` to `path`: `.svg`, or `.html` (an HTML page holding the SVG). PNG
and PDF (`.png`, `.pdf`) need `using Librsvg_jll` (an optional extension);
`scale` multiplies the pixel size of PNG output.
"""
function savefig(path::AbstractString, p::TreePlot; scale::Real=2)
    ext = lowercase(splitext(path)[2])
    if ext == ".svg"
        write(path, render(p))
    elseif ext in (".html", ".htm")
        open(path, "w") do io
            print(io, "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>Tree</title></head>\n",
                  "<body style=\"margin:0;background:", _pagebg(p), "\">\n", render(p), "</body></html>\n")
        end
    elseif ext in (".png", ".pdf")
        _rasterize(path, render(p), ext, Float64(scale))
    else
        throw(ArgumentError("savefig writes .svg, .html, .png or .pdf files; got \"$path\""))
    end
    return path
end

_pagebg(p) = (b = tocolor(p.opt[:theme][:bg]); isvisible(b) ? hexcolor(b) : "#fff")

# replaced by the Librsvg extension
_rasterize(path, svg, ext, scale) = _rasterize(Val(:rsvg), path, svg, ext, scale)
_rasterize(::Val, path, svg, ext, scale) =
    error("saving $ext needs the Librsvg extension: run `using Librsvg_jll` (add it with Pkg if needed), " *
          "or save as .svg")

"""
    preview(p) -> path

Write `p` to a temporary HTML file and open it in the default browser.
"""
function preview(p::TreePlot)
    path = savefig(tempname() * ".html", p)
    cmd = Sys.iswindows() ? `cmd /c start "" $path` : Sys.isapple() ? `open $path` : `xdg-open $path`
    run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
    return path
end

# In an interactive session, a TreePlot goes to the first display that can show
# SVG (VS Code's plot pane, IJulia, Pluto…); in a plain terminal REPL it opens in
# the browser instead of printing a summary.
struct BrowserDisplay <: AbstractDisplay end

function Base.display(::BrowserDisplay, p::TreePlot)
    for d in reverse(Base.Multimedia.displays)
        d isa BrowserDisplay && continue
        d isa TextDisplay && continue
        nameof(typeof(d)) === :REPLDisplay && continue
        displayable(d, MIME"image/svg+xml"()) && return display(d, MIME"image/svg+xml"(), p)
    end
    try
        preview(p)
    catch err
        @warn "could not open a browser; use savefig(\"tree.svg\", p)" exception = err
    end
    return nothing
end
