# API

Tree reading, writing and manipulation (`readnewick`, `readnexus`, `mrca`,
`ladderize!`, `tips`, …) come from
the bundled [PhylogenyIO.jl](https://github.com/EvoArt/PhylogenyIO.jl) source
and are re-exported.

```@docs
PlotPhyloTree
```

## Figure

```@docs
treeplot
PlotPhyloTree.nodevalues
TreePlot
```

## Layers

```@docs
tiplabels!
notiplabels!
highlight!
cladelabel!
colorclade!
colorbranches!
nodepoints!
tippoints!
support!
nodelabels!
nodepies!
nodebars!
timescale!
scalebar!
tipheatmap!
tipbars!
tipimages!
legend!
```

## Output

```@docs
savefig
svgstring
tikzstring
cetzstring
preview
```

## Makie

```@docs
phyloplot
phylofigure
```

## Fonts

```@docs
FontMetrics
fontmetrics
```

## Colours

```@docs
palette
colormap
```
