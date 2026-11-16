module PlotPhyloTreeLibrsvgExt

using PlotPhyloTree
using Librsvg_jll: rsvg_convert

function PlotPhyloTree._rasterize(::Val{:rsvg}, path, svg, ext, scale)
    tmp = tempname() * ".svg"
    write(tmp, svg)
    err = IOBuffer()
    try
        fmt = ext == ".png" ? "png" : "pdf"
        args = fmt == "png" ? `-f png -z $scale` : `-f pdf`
        ok = success(pipeline(`$(rsvg_convert()) $args -o $path $tmp`; stderr=err))
        ok || error("rsvg-convert could not convert the figure: ", strip(String(take!(err))))
    finally
        rm(tmp; force=true)
    end
    return path
end

end
