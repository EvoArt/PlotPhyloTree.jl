# PlotPhyloTree.jl

[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://evoart.github.io/PlotPhyloTree.jl/stable/)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://evoart.github.io/PlotPhyloTree.jl/dev/)
[![CI](https://github.com/EvoArt/PlotPhyloTree.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/EvoArt/PlotPhyloTree.jl/actions/workflows/CI.yml)
[![Coverage](https://codecov.io/gh/EvoArt/PlotPhyloTree.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/EvoArt/PlotPhyloTree.jl)

Phylogenetic tree figures in pure Julia. Rectangular, circular and fan layouts;
clade highlights and labels, support values, node pies, age bars, time scales,
heatmap and bar rings, images and legends. Output to SVG, PNG, PDF, TikZ and
CeTZ (Typst), or into a Makie figure.

> **Work in progress:** in TikZ and CeTZ output, rotated labels and curved
> clade labels can come out at the wrong angle or spacing.

```julia
using Pkg; Pkg.add("PlotPhyloTree")
```

```julia
using PlotPhyloTree, Random
tree = randtree(40; rng=Xoshiro(2), height=50, labels=["Species_$i" for i in 1:40])
ladderize!(tree)
p = treeplot(tree; layout=:circular, italic=true)
highlight!(p, tipnames(tree)[1:9]; label="Clade A")
highlight!(p, tipnames(tree)[24:33]; label="Clade B")
timescale!(p; title="Ma")
savefig("tree.svg", p)
```

<p align="center"><img src="docs/src/assets/readme.png" width="560"></p>

Trees are [PhylogenyIO.jl](https://github.com/EvoArt/PhylogenyIO.jl) `PhyloTree`s,
and its tree API (`readnewick`, `readnexus`, `mrca`, `ladderize!`, …) is
re-exported. Trees built by [PhyloBuilder.jl](https://github.com/EvoArt/PhyloBuilder.jl)
are the same type and can be passed to `treeplot` directly.
