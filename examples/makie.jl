# Makie interface demo. Needs an environment with CairoMakie (or GLMakie) and
# PlotPhyloTree; writes examples/out/makie/*.png.
#   julia --project=<env with CairoMakie> examples/makie.jl
using CairoMakie, PlotPhyloTree, Random

const OUT = joinpath(@__DIR__, "out", "makie")
mkpath(OUT)

rng = Xoshiro(7)
tree = randtree(60; rng, height=100, labels=["Taxon_$i" for i in 1:60])
ladderize!(tree)
for i in internalnodes(tree)
    setdata!(tree, i, :support, rand(rng, [100, 99, 97, 92, 85, 70, 55]))
end
clades = let cl = [rootnode(tree)]
    while length(cl) < 4
        big = argmax(i -> length(tips(tree, i)), cl)
        filter!(!=(big), cl)
        append!(cl, childnodes(tree, big))
    end
    filter(i -> length(tips(tree, i)) >= 4, cl)
end

# 1. a whole figure, sized to the tree
p = treeplot(tree; layout=:circular, branchstyle=:round, italic=true, title="phylofigure (CairoMakie)")
timescale!(p; title="Ma")
highlight!(p, ["Clade $(Char('A' + k - 1))" => i for (k, i) in enumerate(clades)]; branches=true)
support!(p; hidebelow=70)
nodepies!(p, Dict(i => (q = rand(rng); [q, 1 - q]) for i in clades); labels=["state 0", "state 1"], radius=8)
fig = phylofigure(p)
save(joinpath(OUT, "phylofigure.png"), fig; px_per_unit=2)

# 2. composing: a tree beside an ordinary Makie plot
q = treeplot(tree; tiplabels=false, color=:support, title="")
fig = Figure(size=(1000, 500))
ax1 = Axis(fig[1, 1]; aspect=DataAspect(), title="phyloplot! into an Axis")
hidedecorations!(ax1); hidespines!(ax1)
phyloplot!(ax1, q)
ax2 = Axis(fig[1, 2]; title="an ordinary Makie scatter", xlabel="trait 1", ylabel="trait 2")
x = randn(rng, ntips(tree))
scatter!(ax2, x, 0.6x .+ 0.8randn(rng, ntips(tree)); color=:steelblue)
save(joinpath(OUT, "composed.png"), fig; px_per_unit=2)

# 3. rectangular, dated
r = treeplot(tree; title="Rectangular", subtitle="phylofigure(…; scale=1.5)")
nodelabels!(r)
scalebar!(r)
save(joinpath(OUT, "rectangular.png"), phylofigure(r; scale=1.5))
println("done")
