using PlotPhyloTree
using PlotPhyloTree: geometry, render, _fittext, textwidth_px
using Random
using Test

# every element's attributes are unique (a repeated attribute makes the SVG invalid XML)
function wellformed(svg::AbstractString)
    for m in eachmatch(r"<([a-zA-Z]+)((?:\s+[a-zA-Z:-]+=\"[^\"]*\")*)\s*/?>", svg)
        names = [c.captures[1] for c in eachmatch(r"\s([a-zA-Z:-]+)=\"", m.captures[2])]
        allunique(names) || return false
    end
    return startswith(svg, "<svg") && endswith(rstrip(svg), "</svg>")
end
count_tag(svg, tag) = count(_ -> true, eachmatch(Regex("<$tag[\\s>]"), svg))

function testtree(n=24; seed=1)
    rng = Xoshiro(seed)
    t = randtree(n; rng, height=50, labels=["sp_$i" for i in 1:n])
    ladderize!(t)
    for i in internalnodes(t)
        setdata!(t, i, :support, rand(rng, [100, 95, 80, 60]))
        age = treeheight(t) - rootdistance(t)[i]
        setdata!(t, i, Symbol("height_95%_HPD"), [0.9age, 1.1age])
    end
    return t
end

function clades(t, k)
    cl = [rootnode(t)]
    while length(cl) < k
        big = argmax(i -> length(tips(t, i)), cl)
        filter!(!=(big), cl)
        append!(cl, childnodes(t, big))
    end
    return cl
end

@testset "PlotPhyloTree" begin
    t = testtree()
    names = tipnames(t)

    @testset "layouts × layers" begin
        for layout in (:rectangular, :circular, :fan, :dendrogram), style in (:square, :round, :curved, :slanted)
            p = treeplot(t; layout, branchstyle=style, title="T", subtitle="s")
            cl = clades(t, 3)
            highlight!(p, ["A" => cl[1], "B" => cl[2]])
            cladelabel!(p, cl[3], "C"; level=2)
            support!(p)
            nodelabels!(p)
            nodepies!(p, Dict(cl[1] => [1, 2], cl[2] => [3, 1]); labels=["x", "y"])
            nodebars!(p)
            timescale!(p; geo=:epochs)
            tipheatmap!(p, (; a=Dict(n => rand() for n in names), b=Dict(n => rand(["u", "v"]) for n in names)))
            tipbars!(p, Dict(n => rand() for n in names))
            tippoints!(p; color=:red)
            scalebar!(p)
            svg = render(p)
            @test wellformed(svg)
            @test count_tag(svg, "text") > ntips(t)
        end
    end

    @testset "input forms" begin
        nwk = "((a:1,b:1)90:1,(c:1,d:1)70:2);"
        @test ntips(treeplot(nwk).tree) == 4
        path = tempname() * ".nwk"
        write(path, nwk)
        @test ntips(treeplot(path).tree) == 4
        @test_throws ArgumentError treeplot(t; layout=:spiral)
        @test_throws ArgumentError treeplot(t; branchstyle=:wiggly)
    end

    @testset "themes and colour bar" begin
        for theme in (:light, :dark, :minimal)
            svg = render(treeplot(t; theme, color=rand(nnodes(t))))
            @test wellformed(svg)
            @test occursin("fill=\"url(#cb", svg)      # gradient fill written once, as the fill
        end
    end

    @testset "integer colours are palette entries" begin
        p = treeplot(t)
        tipbars!(p, Dict(n => 1.0 for n in names); color=2)
        @test isempty(p.layers[end].legend)             # no spurious colour bar
        @test p.layers[end].colors[tips(t)[1]] == palette(:default)[2]
    end

    @testset "SVG images are inlined" begin
        p = treeplot(t; layout=:circular)
        img = """<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"><rect width="20" height="10"/></svg>"""
        tipimages!(p, Dict(names[1] => img))
        svg = render(p)
        @test wellformed(svg)
        @test occursin(r"<svg x=\"[-\d.]+\" y=\"[-\d.]+\" width=\"40\" height=\"20\"", svg)
        @test occursin("viewBox=\"0 0 20 10\"", svg)
        @test !occursin("<?xml", svg[2:end])
    end

    @testset "clade label rings follow level, not insertion order" begin
        p = treeplot(t; layout=:circular)
        cl = clades(t, 2)
        cladelabel!(p, cl[1], "outer"; level=2)
        cladelabel!(p, cl[2], "inner"; level=1)
        ctx = geometry(p)
        @test ctx.bands[(:cladelabel, 1)][2] <= ctx.bands[(:cladelabel, 2)][1]
    end

    @testset "nested highlights end at their own label ring" begin
        p = treeplot(t; layout=:circular)
        cl = clades(t, 2)
        highlight!(p, cl[1]; label="Order", level=2)
        highlight!(p, first(childnodes(t, cl[1])); label="Family")
        ctx = geometry(p)
        hs = filter(l -> l isa PlotPhyloTree.Highlight, p.layers)
        r_order = PlotPhyloTree._hl_to(ctx, hs[1].to, hs[1].level)
        r_family = PlotPhyloTree._hl_to(ctx, hs[2].to, hs[2].level)
        @test r_family < r_order
        @test r_order ≈ ctx.bands[(:cladelabel, 2)][2] + 4
        # nested (smaller) clades are drawn on top
        svg = render(p)
        @test wellformed(svg)
    end

    @testset "text fitting" begin
        s, fs = _fittext("Short", 10.0, 1000.0)
        @test (s, fs) == ("Short", 10.0)
        s, fs = _fittext("A rather long clade name", 10.0, 60.0)
        @test textwidth_px(s, fs) <= 60
        @test fs >= 6.5
        @test endswith(s, "…")
    end

    @testset "support labels avoid short branches" begin
        tr = parsenewick("((a:10,(b:0.2,c:5)99:0.2)87:10,d:20);")
        p = treeplot(tr)
        nodelabels!(p)
        svg = render(p)
        @test occursin(">87</text>", svg) && occursin(">99</text>", svg)
        ctx = geometry(p)
        node99 = findfirst(i -> getdata(tr, i, :support) == 99, 1:nnodes(tr))
        m = match(r"<text x=\"([-\d.]+)\"[^>]*>99</text>", svg)
        @test m !== nothing
        @test parse(Float64, m.captures[1]) > ctx.r[node99]       # placed after the node
    end

    @testset "compact sizing without tip labels" begin
        big = randtree(300; rng=Xoshiro(2))
        with = geometry(treeplot(big; layout=:circular)).R
        without = geometry(treeplot(big; layout=:circular, tiplabels=false)).R
        @test without < with
    end

    @testset "saving" begin
        p = treeplot(t)
        for ext in (".svg", ".html")
            f = tempname() * ext
            savefig(f, p)
            @test filesize(f) > 1000
        end
        @test_throws ArgumentError savefig(tempname() * ".gif", p)
        @test sprint(show, p) == "TreePlot(24 tips, rectangular, 1 layers)"
        @test showable(MIME"image/svg+xml"(), p)
    end
end
