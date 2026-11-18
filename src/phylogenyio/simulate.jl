# Random trees, for examples and tests.

"""
    randtree(n; model=:yule, rng=Random.default_rng(), labels=["t1", …], height=nothing) -> PhyloTree

A random ultrametric tree with `n` tips. `model = :yule` gives a pure-birth
tree (rate 1); `model = :coalescent` gives a Kingman coalescent tree. When
`height` is given the tree is rescaled to that root-to-tip distance.
"""
function randtree(n::Integer; model::Symbol=:yule, rng::AbstractRNG=Random.default_rng(),
                  labels=["t$i" for i in 1:n], height=nothing)
    n >= 1 || throw(ArgumentError("need at least one tip"))
    length(labels) == n || throw(ArgumentError("need $n labels"))
    model in (:yule, :coalescent) || throw(ArgumentError("model must be :yule or :coalescent"))
    # merge lineages backwards in time: node k > n joins two earlier ones
    nodeh = zeros(2n - 1)
    kids = [Int[] for _ in 1:2n-1]
    live = collect(1:n)
    h = 0.0
    for k in n+1:2n-1
        m = length(live)
        rate = model === :yule ? m : m * (m - 1) / 2
        h += randexp(rng) / rate
        a = popat!(live, rand(rng, 1:length(live)))
        b = popat!(live, rand(rng, 1:length(live)))
        kids[k] = [a, b]
        nodeh[k] = h
        push!(live, k)
    end
    s = height === nothing || h == 0 ? 1.0 : height / h
    t = PhyloTree()
    function build(k, parent, ph)
        i = addnode!(t; parent, length=parent == 0 ? NaN : (ph - nodeh[k]) * s,
                     label=k <= n ? String(labels[k]) : "")
        for c in kids[k]
            build(c, i, nodeh[k])
        end
    end
    build(2n - 1, 0, 0.0)
    return t
end
