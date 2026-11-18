using Documenter, PlotPhyloTree

makedocs(
    sitename = "PlotPhyloTree.jl",
    modules = [PlotPhyloTree],
    format = Documenter.HTML(prettyurls = get(ENV, "CI", nothing) == "true", size_threshold = 2^22),
    pages = [
        "Home" => "index.md",
        "Gallery" => "gallery.md",
        "Makie" => "makie.md",
        "TikZ / LaTeX" => "tikz.md",
        "CeTZ / Typst" => "typst.md",
        "API" => "api.md",
    ],
    # The temporary bundled PhylogenyIO module has its own separate manual.
    checkdocs = :none,
)

deploydocs(repo = "github.com/EvoArt/PlotPhyloTree.jl.git", devbranch = "main")
