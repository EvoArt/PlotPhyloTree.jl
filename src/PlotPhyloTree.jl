"""
    PlotPhyloTree

Publication-quality phylogenetic tree figures in pure Julia, drawn as SVG
(PNG/PDF with the Librsvg extension). Rectangular, circular and fan layouts,
clade highlights and labels, support symbols, ancestral-state pies, node age
bars, time scales with geological colours, heatmap and bar rings, and images.

```julia
using PlotPhyloTree
tree = randtree(40)
p = treeplot(tree; layout=:circular)
highlight!(p, tipnames(tree)[1:8]; label="Clade A")
savefig("tree.svg", p)
```
"""
module PlotPhyloTree

using Base64: base64encode, base64decode
using PhyloIO
using PhyloIO: PhyloTree

# re-export the tree API so `using PlotPhyloTree` is enough
export PhyloTree, nnodes, ntips, isleaf, isroot, parentnode, childnodes, branchlength, nodelabel, rootnode,
       getdata, setdata!, preorder, postorder, tips, tipnames, internalnodes, descendants, ancestors,
       findnode, mrca, nodeindex, rootdistance, treeheight, ladderize!, rotatenode!, sorttips!, keeptips,
       reroot, parsenewick, readnewick, writenewick, readnexus, randtree

export TreePlot, treeplot, tiplabels!, notiplabels!, highlight!, cladelabel!, colorclade!, colorbranches!,
       nodepoints!, tippoints!, support!, nodelabels!, nodepies!, nodebars!, timescale!, scalebar!,
       tipheatmap!, tipbars!, tipimages!, legend!, savefig, preview, svgstring, tikzstring, cetzstring,
       palette, colormap, phyloplot, phyloplot!, phylofigure

include("colors.jl")
include("text.jl")
include("canvas.jl")
include("svg.jl")
include("collide.jl")
include("coords.jl")
include("plot.jl")
include("layers.jl")
include("rings.jl")
include("legend.jl")
include("io.jl")
include("tikz.jl")
include("cetz.jl")
include("makie.jl")

function __init__()
    if isinteractive() && !any(d -> d isa BrowserDisplay, Base.Multimedia.displays)
        pushdisplay(BrowserDisplay())
    end
    return nothing
end

end
