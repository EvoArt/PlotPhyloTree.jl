# PlotPhyloTree.jl

[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://evoart.github.io/PlotPhyloTree.jl/stable/)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://evoart.github.io/PlotPhyloTree.jl/dev/)
[![CI](https://github.com/EvoArt/PlotPhyloTree.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/EvoArt/PlotPhyloTree.jl/actions/workflows/CI.yml)

Phylogenetic tree figures in pure Julia. Rectangular, circular and fan layouts;
clade highlights and labels, support values, node pies, age bars, time scales,
heatmap and bar rings, images and legends. Output to SVG, PNG, PDF, TikZ and
CeTZ (Typst), or into a Makie figure.

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

Trees are read with [PhyloIO.jl](https://github.com/EvoArt/PhyloIO.jl)
(`readnewick`, `readnexus`), re-exported by this package.
