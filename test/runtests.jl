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

    @testset "display list" begin
        p = treeplot(t; layout=:circular, title="T")
        highlight!(p, clades(t, 2)[1]; label="A")
        nodelabels!(p)
        sc = PlotPhyloTree.scene(p)
        @test sc.width > 0 && sc.height > 0
        texts = PlotPhyloTree.TextPrim[]
        PlotPhyloTree.foreachprim(q -> q isa PlotPhyloTree.TextPrim && push!(texts, q), sc.prims)
        @test count(q -> replace(q.text, ' ' => '_') in names, texts) == ntips(t)   # labels show _ as space
        # arcs: Bézier pieces and flattened points stay on the circle
        s = PlotPhyloTree.Seg('A', 10cos(2.0), 10sin(2.0), 0.0, 0.0, 10.0, 0.3, 2.0)
        for (c1, c2, e) in PlotPhyloTree._arcbeziers(s)
            @test hypot(e...) ≈ 10
        end
        pb = PlotPhyloTree.PathBuilder()
        PlotPhyloTree.M!(pb, 10cos(0.3), 10sin(0.3))
        PlotPhyloTree.arc!(pb, 0, 0, 10, 0.3, 2.0)
        PlotPhyloTree.Z!(pb)
        ((pts, closed),) = PlotPhyloTree._polylines(pb.segs)
        @test closed && all(q -> hypot(q...) ≈ 10, pts)
        @test pts[end] == (10cos(2.0), 10sin(2.0))
    end

    @testset "TikZ" begin
        p = treeplot(t; layout=:circular, title="Tree_1 & co", color=rand(nnodes(t)))
        highlight!(p, clades(t, 2)[1]; label="A")
        support!(p)
        nodelabels!(p)
        tex = tikzstring(p)
        @test startswith(tex, "% PlotPhyloTree figure") && endswith(tex, "\\end{tikzpicture}\n")
        @test count('{', tex) == count('}', tex)
        @test occursin("arc[start angle=", tex)
        @test occursin("Tree\\_1 \\& co", tex)
        @test occursin("\\shade[left color=", tex)                  # colour bar
        @test occursin("\\ensuremath{\\geq}", tex)                  # support legend "≥ 0.95"
        @test !occursin(r"[≥≤]", tex)
        @test occursin(r"\\node\[anchor=base west, inner sep=0pt", tex)
        doc = tikzstring(p; standalone=true, scale=0.5)
        @test startswith(doc, "\\documentclass") && endswith(doc, "\\end{document}\n")
        @test occursin("line width=0.5bp", doc) || occursin("line width=0.", doc)
        @test PlotPhyloTree._tikzesc("50% a_b {x} ~ ^ \\ α") ==
              "50\\% a\\_b \\{x\\} \\textasciitilde{} \\^{} \\textbackslash{} \\ensuremath{\\alpha}"
    end

    @testset "CeTZ" begin
        p = treeplot(t; layout=:fan, title="Say \"hi\"", color=rand(nnodes(t)))
        highlight!(p, clades(t, 2)[1]; label="A")
        nodelabels!(p)
        typ = cetzstring(p)
        @test startswith(typ, "// PlotPhyloTree figure")
        @test occursin("#import \"@preview/cetz:$(PlotPhyloTree.CETZ_VERSION)\"", typ)
        @test occursin("#context cetz.canvas(length: 1pt, {", typ)
        @test occursin("merge-path(", typ) && occursin("bezier(", typ)
        @test occursin("gradient.linear(", typ)
        @test occursin("\"Say \\\"hi\\\"\"", typ)
        @test occursin("anchor: \"base-west\"", typ)
        @test occursin("top-edge: \"cap-height\", bottom-edge: \"baseline\"", typ)
        @test !occursin("#set page", typ)
        doc = cetzstring(p; standalone=true, cetz="0.3.0")
        @test occursin("#set page(width: auto, height: auto, margin: 0pt", doc)
        @test occursin("cetz:0.3.0", doc)
    end

    @testset "font metrics" begin
        P = PlotPhyloTree
        @test P._metricsforfont("Helvetica Neue, Helvetica, Arial, sans-serif") === :helvetica
        @test P._metricsforfont("Latin Modern Roman") === :lmroman
        @test P._metricsforfont("Times New Roman, serif") === :times
        w(m; kw...) = P.withmetrics(() -> P.textwidth_px("Species 42", 10; kw...), P._metrics(m))
        @test w(:helvetica) ≈ 49.47
        @test w(:lmroman) < w(:helvetica) && w(:times) < w(:helvetica)
        @test w(:lmroman; italic=true) != w(:lmroman)
        @test P.textwidth_px("Species 42", 10) ≈ 49.47               # Helvetica outside a layout
        @test_throws ArgumentError treeplot(t; metrics=:comic)
        # the layout follows the metrics: narrower labels, smaller figure
        sc_h = P.scene(treeplot(t; layout=:circular))
        sc_lm = P.scene(treeplot(t; layout=:circular, metrics=:lmroman))
        @test sc_lm.metrics.name == "Latin Modern Roman"
        @test sc_lm.width < sc_h.width
        # reading a font file, when the system has one
        ttf = filter(isfile, ["C:/Windows/Fonts/arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                              "/System/Library/Fonts/Supplemental/Arial.ttf"])
        if !isempty(ttf)
            m = fontmetrics(ttf[1])
            @test m isa FontMetrics && 200 < m.regular['a'] < 800 && m.bold['a'] > m.regular['a']
            @test treeplot(t; metrics=m).opt[:metrics] === m
        end
    end

    @testset "curved text and document fonts" begin
        p = treeplot(t; layout=:circular)
        cladelabel!(p, clades(t, 2)[1], "Clade one")
        sc = PlotPhyloTree.scene(p)
        arcs = PlotPhyloTree.ArcTextPrim[]
        PlotPhyloTree.foreachprim(q -> q isa PlotPhyloTree.ArcTextPrim && push!(arcs, q), sc.prims)
        @test length(arcs) == 1 && length(arcs[1].glyphs) == 8                 # no glyph for the space
        tex = tikzstring(p)
        @test occursin("decoration={text along path, text align=center, text={|", tex)
        @test occursin("|Clade one}}]", tex)
        @test !occursin("\\sffamily", tex)                                     # the document's font
        @test occursin("\\providecommand\\PlotPhyloTreeFont{}", tex)
        @test occursin("\\selectfont\\PlotPhyloTreeFont\\sffamily", tikzstring(p; font="\\sffamily"))
        glyphs = tikzstring(p; curvedtext=:glyphs)
        @test !occursin("text along path", glyphs) && occursin("{C};", glyphs)
        @test occursin("\\usepackage{tgheros}", tikzstring(p; standalone=true))  # matches Helvetica metrics
        q = treeplot(t; layout=:circular, metrics=:lmroman)
        cladelabel!(q, clades(t, 2)[1], "Clade one")
        @test occursin("\\usepackage{lmodern}", tikzstring(q; standalone=true))
        typ = cetzstring(p)
        @test occursin("measure(text(..st, c))", typ) && occursin("\"Clade one\".clusters()", typ)
        @test !occursin("#set text(font", typ)                                 # included: document font
        @test occursin("#set text(font: (\"Latin Modern Roman\"", cetzstring(q; standalone=true))
        @test occursin("#set text(font: (\"Fira Sans\",)", cetzstring(q; font="Fira Sans"))
        @test !occursin("measure(", cetzstring(p; curvedtext=:glyphs))
    end

    @testset "saving TikZ and Typst with images" begin
        p = treeplot(t; layout=:circular)
        img = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"""
        tipimages!(p, Dict(names[1] => img))
        dir = mktempdir()
        f = savefig(joinpath(dir, "fig.typ"), p)
        @test isfile(joinpath(dir, "fig-img-1.svg"))
        @test occursin("image(\"fig-img-1.svg\"", read(f, String))
        @test occursin("#set page", read(f, String))
        savefig(joinpath(dir, "inc.typ"), p; standalone=false)
        @test !occursin("#set page", read(joinpath(dir, "inc.typ"), String))
        # TikZ: SVG images need converting to PDF (Librsvg extension, not loaded here)
        tex = @test_logs (:warn, r"SVG image 1") match_mode = :any savefig(joinpath(dir, "fig.tex"), p)
        @test startswith(read(tex, String), "\\documentclass")
        savefig(joinpath(dir, "fig.tikz"), p)
        @test startswith(read(joinpath(dir, "fig.tikz"), String), "% PlotPhyloTree")
        # a PNG data URI is decoded and written beside the file
        png = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, zeros(UInt8, 8)..., 0, 0, 0, 2, 0, 0, 0, 1]
        q = treeplot(t)
        tipimages!(q, Dict(names[2] => "data:image/png;base64," * PlotPhyloTree.base64encode(png)))
        savefig(joinpath(dir, "png.tex"), q)
        @test read(joinpath(dir, "png-img-1.png")) == png
        @test occursin("{png-img-1.png}", read(joinpath(dir, "png.tex"), String))
        @test_throws ArgumentError savefig(joinpath(dir, "x.svg"), q; standalone=true)
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

    @testset "label collisions" begin
        PT = PlotPhyloTree
        leaves(prims) = (v = PT.Prim[]; PT.foreachprim(x -> push!(v, x), prims); v)
        # does `x` overlap anything in `others`?
        function clashes(x, others)
            cl = PT.Collider()
            for o in others
                PT._addprim!(cl, o)
            end
            q = x isa PT.TextPrim ? PT._textquad(x) : PT._rectpts(x.x, x.y, x.w, x.h)
            return PT.collides(cl, q)
        end

        @testset "geometry" begin
            sq = PT._rectpts(0, 0, 10, 10)
            @test PT._convex_overlap(sq, PT._rectpts(5, 5, 10, 10))
            @test !PT._convex_overlap(sq, PT._rectpts(11, 0, 5, 5))
            @test PT._convex_overlap(sq, [(-5.0, 5.0), (15.0, 5.0)])          # a segment through it
            @test !PT._convex_overlap(sq, [(-5.0, 12.0), (15.0, 30.0)])
            @test PT._inside((5.0, 5.0), sq) && !PT._inside((15.0, 5.0), sq)
        end

        @testset "soft labels take the first free candidate" begin
            c = PT.Canvas()
            PT.line!(c, -50, 0, 50, 0; color=:black)
            cand(y) = (; x=0.0, y, text="label", fontsize=10.0, halign=:center)
            PT.softtext!(c, [cand(0.0), cand(20.0)])                    # first one sits on the line
            PT.softtext!(c, [cand(0.0)])                                # nowhere free: dropped
            PT.softtext!(c, [cand(0.0)]; required=true)                 # nowhere free: drawn anyway
            PT.softtext!(c, [cand(20.0), cand(40.0)])                   # 20 is taken by the first label
            PT.resolve_labels!(c)
            ts = [x for x in leaves(c.prims) if x isa PT.TextPrim]
            @test [t.y for t in ts] == [20.0, 0.0, 40.0]
            @test !any(x -> x isa PT.SoftTextPrim, leaves(c.prims))
            @test c.bbox.ymax >= 40
            # wedges, bands and grid lines never block a label
            c2 = PT.Canvas()
            pb = PT.PathBuilder(); PT.M!(pb, -50, -50); PT.L!(pb, 50, -50); PT.L!(pb, 50, 50); PT.Z!(pb)
            PT.path!(c2, pb; fill=:red, class="highlight")
            PT.softtext!(c2, [cand(0.0)])
            PT.resolve_labels!(c2)
            @test only(x for x in leaves(c2.prims) if x isa PT.TextPrim).y == 0.0
        end

        @testset "time-scale names keep off the tree" begin
            tr = randtree(70; rng=Xoshiro(11), height=100)
            ladderize!(tr)
            p = treeplot(tr; layout=:circular, openangle=20)
            timescale!(p; geo=:periods, title="Ma")
            s = PT.scene(p)
            prims = leaves(s.prims)
            geonames = Set(vcat([[g[1], g[2]] for g in PT.GEO_PERIODS]...))
            placed = [x for x in prims if x isa PT.TextPrim && x.text in geonames]
            @test !isempty(placed)
            for g in placed
                @test !clashes(g, filter(x -> x !== g, prims))
            end
            @test !any(x -> x isa PT.SoftTextPrim, prims)
        end

        @testset "support labels and legend avoid everything" begin
            tr = randtree(40; rng=Xoshiro(5))
            for i in internalnodes(tr)
                setdata!(tr, i, :support, 99)
            end
            p = treeplot(tr; layout=:circular)
            nodelabels!(p; hideoverlaps=true)
            support!(p)
            s = PT.scene(p)
            prims = leaves(s.prims)
            labels = [x for x in prims if x isa PT.TextPrim && x.text == "99"]
            @test !isempty(labels)
            @test all(l -> !clashes(l, filter(x -> x !== l, prims)), labels)
            lg = only(x for x in s.prims if x isa PT.GroupPrim && x.class == "legend")
            others = [x for x in prims if !(x in leaves(lg.children))]
            for x in leaves(lg.children)
                x isa Union{PT.TextPrim,PT.RectPrim} && @test !clashes(x, others)
            end
        end
    end
end
