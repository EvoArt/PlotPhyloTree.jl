# Makie interface: implemented in the PlotPhyloTreeMakieExt extension, which
# loads with Makie (or any Makie backend: CairoMakie, GLMakie, WGLMakie).

"""
    phyloplot(tree_or_plot; kwargs...)
    phyloplot!(ax, tree_or_plot; kwargs...)

Draw a tree figure with Makie (needs `using CairoMakie`, `GLMakie`, … — the
Makie extension). The argument is a [`TreePlot`](@ref) built with
[`treeplot`](@ref) and its layers, or a tree (a `PhyloTree`, Newick string or
file), which is drawn with `treeplot`'s defaults.

The figure is laid out exactly as for SVG and translated into Makie plots
(`poly`, `lines`, `text`, `image`), so it composes with other plots: one
data unit is one px of the layout, with y pointing up and the tree's root
region near the origin of the layout. Use [`phylofigure`](@ref) for a
ready-made `Figure` sized to the tree.

Attributes:
- `linewidthscale = 1` — Makie line widths are in screen px, not data
  units; scale them when the axis is drawn larger or smaller than the layout.
- `fontscale = 1` — multiplies label sizes (text is sized in data units).
- `images = true` — draw `tipimages!` images (decoded with FileIO; SVG
  images are skipped).
"""
function phyloplot end
function phyloplot! end

"""
    phylofigure(p; scale=1, kwargs...) -> Makie.FigureAxisPlot

A Makie `Figure` holding one `Axis` with [`phyloplot`](@ref)`(p)`, sized so
one px of the layout is `scale` screen px, with the axis decorations hidden
and an equal aspect ratio. Other keywords go to `phyloplot`. Needs a Makie
backend to be loaded.
"""
function phylofigure end
