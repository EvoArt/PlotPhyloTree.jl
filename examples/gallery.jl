# Gallery: every layer in every layout. Writes examples/out/gallery/*.{png,svg},
# plus TikZ (tikz/*.tex) and CeTZ (typst/*.typ) versions.
# Run: julia --project=examples examples/gallery.jl [name ...]
using PlotPhyloTree, Librsvg_jll, Random

const OUT = joinpath(@__DIR__, "out", "gallery")
mkpath(OUT)

# a dated tree with BEAST-style annotations
function datedtree(n; seed=1, height=60)
    rng = Xoshiro(seed)
    t = randtree(n; rng, height, labels=["Species_$(i)" for i in 1:n])
    ladderize!(t)
    H = treeheight(t)
    x = rootdistance(t)
    for i in internalnodes(t)
        age = H - x[i]
        w = 0.08 * age + 1
        setdata!(t, i, Symbol("height_95%_HPD"), [max(age - w * rand(rng), 0.0), age + w * rand(rng)])
        setdata!(t, i, :posterior, rand(rng, [1.0, 1.0, 0.99, 0.97, 0.9, 0.8, 0.6]))
    end
    for i in 1:nnodes(t)
        setdata!(t, i, :rate, exp(0.4 * randn(rng)))
    end
    return t, rng
end

# a few clades in drawing order, found by splitting the largest
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

# simple SVG "silhouettes" so the example needs no image files
function blob(col, k)
    pts = join(("$(round(50 + (30 + 12 * sin(3a + k)) * cos(a); digits=1)),$(round(50 + (30 + 12 * sin(3a + k)) * sin(a); digits=1))"
                for a in range(0, 2π; length=40)[1:end-1]), " ")
    """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><polygon points="$pts" fill="$col"/></svg>"""
end

mkpath(joinpath(OUT, "tikz")); mkpath(joinpath(OUT, "typst"))
function save(name, p)
    savefig(joinpath(OUT, name * ".png"), p; scale=1.5)
    savefig(joinpath(OUT, name * ".svg"), p)
    savefig(joinpath(OUT, "tikz", name * ".tex"), p)      # compile with pdflatex
    savefig(joinpath(OUT, "typst", name * ".typ"), p)     # compile with typst
    println("  ", name)
end

const GALLERY = Dict{String,Function}()

GALLERY["rect_basic"] = () -> begin
    t, _ = datedtree(30)
    p = treeplot(t; title="Rectangular", subtitle="square branches, scale bar, support labels")
    nodelabels!(p; text=:posterior)
    scalebar!(p)
    save("rect_basic", p)
end

GALLERY["rect_dated"] = () -> begin
    t, _ = datedtree(36; seed=3, height=80)
    p = treeplot(t; italic=true, title="Dated tree", subtitle="HPD bars, epochs, posterior symbols")
    timescale!(p; geo=:epochs, title="Ma")
    nodebars!(p)
    support!(p; key=:posterior)
    save("rect_dated", p)
end

GALLERY["rect_data"] = () -> begin
    t, rng = datedtree(28; seed=5)
    names = tipnames(t)
    cl = someclades(t, 4)
    p = treeplot(t; branchstyle=:round, align=true, color=:rate, colortitle="Rate", colormap=:viridis)
    for (k, i) in enumerate(cl)
        highlight!(p, i; label="Group $k")
    end
    tipheatmap!(p, (; mass=Dict(n => rand(rng) * 10 for n in names),
                    habitat=Dict(n => rand(rng, ["forest", "grassland", "wetland"]) for n in names)))
    tipbars!(p, Dict(n => rand(rng) * 100 for n in names); title="Range size")
    save("rect_data", p)
end

GALLERY["rect_styles"] = () -> begin
    t, _ = datedtree(16; seed=2)
    for s in (:square, :round, :curved, :slanted)
        save("style_$s", treeplot(t; branchstyle=s, title=string(s)))
    end
end

GALLERY["directions"] = () -> begin
    t, _ = datedtree(14; seed=4)
    for d in (:left, :down, :up)
        p = treeplot(t; direction=d, title="direction = :$d")
        timescale!(p)
        cl = someclades(t, 3)
        cladelabel!(p, cl[1], "First"; color=1)
        save("dir_$d", p)
    end
    save("dendrogram", treeplot(t; layout=:dendrogram, cladogram=true, title="dendrogram, cladogram"))
end

GALLERY["circular_data"] = () -> begin
    t, rng = datedtree(70; seed=11, height=100)
    names = tipnames(t)
    cl = someclades(t, 5; minsize=5)
    p = treeplot(t; layout=:circular, openangle=20, title="Circular with rings")
    timescale!(p; geo=:periods)
    highlight!(p, ["Clade $k" => c for (k, c) in enumerate(cl)])
    tipheatmap!(p, (; trait=Dict(n => rand(rng) for n in names),
                    diet=Dict(n => rand(rng, ["herbivore", "carnivore"]) for n in names)))
    tipbars!(p, Dict(n => rand(rng) for n in names); color=:gray50)
    tipimages!(p, Dict(tips(t, c)[1] => blob(PlotPhyloTree.hexcolor(palette(:default)[k]), k) for (k, c) in enumerate(cl));
               size=30)
    save("circular_data", p)
end

GALLERY["fan"] = () -> begin
    t, rng = datedtree(50; seed=8)
    cl = someclades(t, 4)
    p = treeplot(t; layout=:fan, branchstyle=:curved, title="Fan", fontsize=8)
    highlight!(p, Dict("Clade $k" => c for (k, c) in enumerate(cl)); branches=true)
    tippoints!(p; color=Dict(n => rand(rng, ["a", "b", "c"]) for n in tipnames(t)), title="State")
    timescale!(p)
    save("fan", p)
end

GALLERY["dark"] = () -> begin
    t, rng = datedtree(60; seed=13)
    cl = someclades(t, 4)
    p = treeplot(t; layout=:circular, theme=:dark, inner=30, rootedge=10, color=:rate, colormap=:magma,
                 colortitle="Rate", title="Dark theme")
    for (k, c) in enumerate(cl)
        cladelabel!(p, c, "Clade $k"; color=k)
    end
    cladelabel!(p, cl[1], "Superclade"; level=2, color=:gray60)
    save("dark", p)
end

GALLERY["nested"] = () -> begin
    t, _ = datedtree(40; seed=21)
    cl = someclades(t, 3)
    sub = vcat((someclades_from(t, c) for c in cl)...)
    p = treeplot(t; layout=:circular, title="Nested highlights and labels")
    for (k, c) in enumerate(cl)
        highlight!(p, c; label="Order $k", level=2, alpha=0.15)
    end
    for (k, c) in enumerate(sub)
        highlight!(p, c; label="F$k", alpha=0.25, color=k + 4)
    end
    save("nested", p)
end
someclades_from(t, i) = [c for c in childnodes(t, i) if length(tips(t, c)) >= 3]

GALLERY["big"] = () -> begin
    t, _ = datedtree(400; seed=31)
    p = treeplot(t; layout=:circular, tiplabels=false, color=:rate, title="400 tips, no labels")
    save("big", p)
end

which = isempty(ARGS) ? sort(collect(keys(GALLERY))) : ARGS
for name in which
    try
        GALLERY[name]()
    catch err
        println("  ", name, " FAILED: ", sprint(showerror, err))
    end
end
