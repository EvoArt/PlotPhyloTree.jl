# Gallery

Each panel uses a random dated tree with BEAST-style node annotations, made by
this helper:

```@example gallery
using PlotPhyloTree, Random

function datedtree(n; seed=1, height=60)
    rng = Xoshiro(seed)
    t = randtree(n; rng, height, labels=["Species_$i" for i in 1:n])
    ladderize!(t)
    H = treeheight(t)
    x = rootdistance(t)
    for i in internalnodes(t)
        age = H - x[i]
        w = 0.08age + 1
        setdata!(t, i, Symbol("height_95%_HPD"), [max(age - w * rand(rng), 0.0), age + w * rand(rng)])
        setdata!(t, i, :posterior, rand(rng, [1.0, 1.0, 0.99, 0.97, 0.9, 0.8, 0.6]))
    end
    for i in 1:nnodes(t)
        setdata!(t, i, :rate, exp(0.4randn(rng)))
    end
    return t, rng
end

# k clades, found by repeatedly splitting the largest
function someclades(t, k; minsize=3)
    cl = [rootnode(t)]
    while length(cl) < k
        big = argmax(i -> length(tips(t, i)), cl)
        filter!(!=(big), cl)
        append!(cl, childnodes(t, big))
    end
    rank = Dict(i => k for (k, i) in enumerate(tips(t)))
    return sort!(filter!(i -> length(tips(t, i)) >= minsize, cl); by=i -> rank[first(tips(t, i))])
end
nothing # hide
```

## Rectangular

```@example gallery
t, _ = datedtree(30)
p = treeplot(t)
nodelabels!(p; text=:posterior)
scalebar!(p)
p
```

## Dated tree

```@example gallery
t, _ = datedtree(36; seed=3, height=80)
p = treeplot(t; italic=true)
timescale!(p; geo=:epochs, title="Ma")
nodebars!(p)
support!(p; key=:posterior)
p
```

## Tip data

```@example gallery
t, rng = datedtree(28; seed=5)
names = tipnames(t)
p = treeplot(t; branchstyle=:round, align=true, color=:rate, colortitle="Rate", colormap=:viridis)
for (k, i) in enumerate(someclades(t, 4))
    highlight!(p, i; label="Group $k")
end
tipheatmap!(p, (; mass=Dict(n => 10rand(rng) for n in names),
                habitat=Dict(n => rand(rng, ["forest", "grassland", "wetland"]) for n in names)))
tipbars!(p, Dict(n => 100rand(rng) for n in names); title="Range size")
p
```

## Branch styles

`branchstyle` is `:square` (default), `:round`, `:curved` or `:slanted`.

```@example gallery
t, _ = datedtree(16; seed=2)
treeplot(t; branchstyle=:curved)
```

## Direction

`direction` is `:right` (default), `:left`, `:down` or `:up`.

```@example gallery
t, _ = datedtree(14; seed=4)
p = treeplot(t; direction=:down)
timescale!(p)
cladelabel!(p, someclades(t, 3)[1], "First"; color=1)
p
```

## Dendrogram

```@example gallery
treeplot(t; layout=:dendrogram, cladogram=true)
```

## Circular with rings

```@example gallery
t, rng = datedtree(70; seed=11, height=100)
names = tipnames(t)
cl = someclades(t, 5; minsize=5)
p = treeplot(t; layout=:circular, openangle=20)
timescale!(p; geo=:periods)
highlight!(p, ["Clade $k" => c for (k, c) in enumerate(cl)])
tipheatmap!(p, (; trait=Dict(n => rand(rng) for n in names),
                diet=Dict(n => rand(rng, ["herbivore", "carnivore"]) for n in names)))
tipbars!(p, Dict(n => rand(rng) for n in names); color=:gray50)
p
```

## Fan

```@example gallery
t, rng = datedtree(50; seed=8)
p = treeplot(t; layout=:fan, branchstyle=:curved, fontsize=8)
highlight!(p, Dict("Clade $k" => c for (k, c) in enumerate(someclades(t, 4))); branches=true)
tippoints!(p; color=Dict(n => rand(rng, ["a", "b", "c"]) for n in tipnames(t)), title="State")
timescale!(p)
p
```

## Clade labels, dark theme

```@example gallery
t, _ = datedtree(60; seed=13)
cl = someclades(t, 4)
p = treeplot(t; layout=:circular, theme=:dark, inner=30, rootedge=10,
             color=:rate, colormap=:magma, colortitle="Rate")
for (k, c) in enumerate(cl)
    cladelabel!(p, c, "Clade $k"; color=k)
end
cladelabel!(p, cl[1], "Superclade"; level=2, color=:gray60)
p
```

## Nested highlights

```@example gallery
t, _ = datedtree(40; seed=21)
cl = someclades(t, 3)
sub = [c for i in cl for c in childnodes(t, i) if length(tips(t, c)) >= 3]
p = treeplot(t; layout=:circular)
for (k, c) in enumerate(cl)
    highlight!(p, c; label="Order $k", level=2, alpha=0.15)
end
for (k, c) in enumerate(sub)
    highlight!(p, c; label="F$k", alpha=0.25, color=k + 4)
end
p
```

## Ancestral states

```@example gallery
t, rng = datedtree(24; seed=6)
p = treeplot(t; layout=:circular)
nodepies!(p, Dict(i => (q = rand(rng); [q, 1 - q]) for i in internalnodes(t));
          labels=["state 0", "state 1"])
p
```

## Large tree

```@example gallery
t, _ = datedtree(400; seed=31)
treeplot(t; layout=:circular, tiplabels=false, color=:rate)
```
