# Demo: circular tree with clade highlights, support, pies and a time scale.
# Run: julia --project=examples examples/demo.jl
using PlotPhyloTree, Librsvg_jll, Random

rng = Xoshiro(7)
tree = randtree(80; rng, height=100, labels=["Taxon_$i" for i in 1:80])
ladderize!(tree)
for i in internalnodes(tree)          # simulated support values
    setdata!(tree, i, :support, rand(rng, [100, 99, 97, 92, 85, 70, 55]))
end

# split the largest clade until there are five clades, then name them in drawing order
clades = [rootnode(tree)]
while length(clades) < 5
    big = argmax(i -> length(tips(tree, i)), clades)
    filter!(!=(big), clades)
    append!(clades, childnodes(tree, big))
end
rank = Dict(i => k for (k, i) in enumerate(tips(tree)))      # drawing order of the tips
sort!(filter!(i -> length(tips(tree, i)) >= 4, clades); by=i -> rank[first(tips(tree, i))])

p = treeplot(tree; layout=:circular, branchstyle=:round, italic=true,
             title="PlotPhyloTree", subtitle="simulated 80-tip tree")
timescale!(p; title="Ma", to=:labels)
highlight!(p, ["Clade $(Char('A' + k - 1))" => i for (k, i) in enumerate(clades)]; branches=true)
support!(p; hidebelow=70)
nodepies!(p, Dict(i => (q = rand(rng); [q, 1 - q]) for i in clades); labels=["state 0", "state 1"],
          title="Ancestral state", radius=8)

mkpath(joinpath(@__DIR__, "out"))
savefig(joinpath(@__DIR__, "out", "demo.svg"), p)
savefig(joinpath(@__DIR__, "out", "demo.png"), p; scale=2)
println("done")
