# A rooted tree stored as flat arrays indexed by node number.

"""
    PhyloTree()

A rooted phylogenetic tree. Nodes are numbered `1:nnodes(tree)`; each node has
a parent (`0` for the root), an ordered list of children, a branch length
(`NaN` when missing), a label (`""` when missing) and a dictionary of
annotations (`Dict{Symbol,Any}`), which holds support values and anything read
from NHX or BEAST-style comments.

Build one with [`readnewick`](@ref), [`parsenewick`](@ref),
[`readnexus`](@ref) or [`randtree`](@ref), or node by node with
[`addnode!`](@ref).
"""
mutable struct PhyloTree
    parent::Vector{Int}
    children::Vector{Vector{Int}}
    length::Vector{Float64}
    label::Vector{String}
    data::Vector{Dict{Symbol,Any}}
    root::Int
end

PhyloTree() = PhyloTree(Int[], Vector{Int}[], Float64[], String[], Dict{Symbol,Any}[], 0)

"""
    addnode!(tree; parent=0, length=NaN, label="") -> Int

Add a node to `tree` as the last child of `parent` (or as the root when
`parent == 0`) and return its index.
"""
function addnode!(t::PhyloTree; parent::Integer=0, length::Real=NaN, label::AbstractString="")
    push!(t.parent, parent)
    push!(t.children, Int[])
    push!(t.length, Float64(length))
    push!(t.label, String(label))
    push!(t.data, Dict{Symbol,Any}())
    i = Base.length(t.parent)
    if parent == 0
        t.root == 0 || throw(ArgumentError("tree already has a root"))
        t.root = i
    else
        push!(t.children[parent], i)
    end
    return i
end

"""
    nnodes(tree)

Number of nodes, tips included.
"""
nnodes(t::PhyloTree) = length(t.parent)
"""
    ntips(tree)

Number of tips (leaves).
"""
ntips(t::PhyloTree) = count(isempty, t.children)
"""
    isleaf(tree, i)

Whether node `i` is a tip.
"""
isleaf(t::PhyloTree, i::Integer) = isempty(t.children[i])
"""
    isroot(tree, i)

Whether node `i` is the root.
"""
isroot(t::PhyloTree, i::Integer) = t.parent[i] == 0
"""
    parentnode(tree, i)

Parent of node `i` (`0` for the root).
"""
parentnode(t::PhyloTree, i::Integer) = t.parent[i]
"""
    childnodes(tree, i)

Children of node `i`, in drawing order.
"""
childnodes(t::PhyloTree, i::Integer) = t.children[i]
"""
    branchlength(tree, i)

Length of the branch above node `i` (`NaN` if missing).
"""
branchlength(t::PhyloTree, i::Integer) = t.length[i]
"""
    nodelabel(tree, i)

Label of node `i`.
"""
nodelabel(t::PhyloTree, i::Integer) = t.label[i]
"""
    rootnode(tree)

Index of the root.
"""
rootnode(t::PhyloTree) = t.root

"""
    getdata(tree, i, key, default=nothing)

The annotation `key` (a `Symbol`) of node `i`, or `default`.
"""
getdata(t::PhyloTree, i::Integer, key::Symbol, default=nothing) = get(t.data[i], key, default)

"""
    setdata!(tree, i, key, value)

Set annotation `key` of node `i`.
"""
setdata!(t::PhyloTree, i::Integer, key::Symbol, value) = (t.data[i][key] = value; t)

"""
    preorder(tree, from=root) -> Vector{Int}

Nodes in pre-order (parents before children, children in drawing order).
"""
function preorder(t::PhyloTree, from::Integer=t.root)
    out = Int[]
    stack = [Int(from)]
    while !isempty(stack)
        i = pop!(stack)
        push!(out, i)
        ch = t.children[i]
        for k in length(ch):-1:1
            push!(stack, ch[k])
        end
    end
    return out
end

"""
    postorder(tree, from=root)

Nodes with children before parents.
"""
function postorder(t::PhyloTree, from::Integer=t.root)
    out = Int[]
    stack = [(Int(from), false)]
    while !isempty(stack)
        i, done = pop!(stack)
        if done || isempty(t.children[i])
            push!(out, i)
        else
            push!(stack, (i, true))
            ch = t.children[i]
            for k in length(ch):-1:1
                push!(stack, (ch[k], false))
            end
        end
    end
    return out
end

"""
    tips(tree, from=root)

Tip nodes in drawing order (top to bottom).
"""
tips(t::PhyloTree, from::Integer=t.root) = filter(i -> isleaf(t, i), preorder(t, from))

"""
    tipnames(tree)

Tip labels in drawing order.
"""
tipnames(t::PhyloTree) = [t.label[i] for i in tips(t)]

"""
    internalnodes(tree)

Internal nodes in pre-order.
"""
internalnodes(t::PhyloTree) = filter(i -> !isleaf(t, i), preorder(t))

"""
    descendants(tree, i)

All nodes below `i` (excluding `i`).
"""
descendants(t::PhyloTree, i::Integer) = preorder(t, i)[2:end]

"""
    ancestors(tree, i)

Nodes from the parent of `i` up to the root.
"""
function ancestors(t::PhyloTree, i::Integer)
    out = Int[]
    p = t.parent[i]
    while p != 0
        push!(out, p)
        p = t.parent[p]
    end
    return out
end

"""
    findnode(tree, label) -> Int

The node whose label is `label`. Throws if there is none.
"""
function findnode(t::PhyloTree, name::AbstractString)
    i = findfirst(==(name), t.label)
    if i === nothing
        alt = replace(name, ' ' => '_')
        i = findfirst(==(alt), t.label)
        i === nothing && (i = findfirst(==(replace(name, '_' => ' ')), t.label))
    end
    i === nothing && throw(ArgumentError("no node labelled \"$name\""))
    return i
end

"""
    mrca(tree, nodes) -> Int

Most recent common ancestor of `nodes` (indices or labels).
"""
function mrca(t::PhyloTree, nodes)
    idx = [nodeindex(t, n) for n in nodes]
    isempty(idx) && throw(ArgumentError("mrca of an empty set"))
    path = reverse(vcat(idx[1], ancestors(t, idx[1])))   # root .. node
    depth = length(path)
    for j in idx[2:end]
        anc = Set(vcat(j, ancestors(t, j)))
        while !(path[depth] in anc)
            depth -= 1
        end
    end
    return path[depth]
end
mrca(t::PhyloTree, a, b, rest...) = mrca(t, [a, b, rest...])

"""
    nodeindex(tree, x) -> Int

Resolve a node reference: an index, a label, or a collection of labels or
indices (their MRCA).
"""
nodeindex(t::PhyloTree, i::Integer) = (1 <= i <= nnodes(t) || throw(BoundsError(t.parent, i)); Int(i))
nodeindex(t::PhyloTree, s::AbstractString) = findnode(t, s)
nodeindex(t::PhyloTree, s::Symbol) = findnode(t, String(s))
nodeindex(t::PhyloTree, v::Union{AbstractVector,Tuple,AbstractSet}) = length(v) == 1 ? nodeindex(t, first(v)) : mrca(t, v)

"""
    rootdistance(tree; cladogram=false) -> Vector{Float64}

Distance of every node from the root. Missing branch lengths count as 1 when
the tree has no branch lengths at all, else as 0. With `cladogram = true`
branch lengths are ignored and tips are aligned.
"""
function rootdistance(t::PhyloTree; cladogram::Bool=false)
    n = nnodes(t)
    x = zeros(n)
    haslen = any(i -> i != t.root && !isnan(t.length[i]), 1:n)
    if cladogram
        h = nodeheight_steps(t)
        H = h[t.root]
        for i in 1:n
            x[i] = H - h[i]
        end
        # children of a node sit one step to its right at least
        for i in preorder(t)
            i == t.root && continue
            x[i] = max(x[i], x[t.parent[i]] + 1)
        end
        return x
    end
    for i in preorder(t)
        i == t.root && continue
        l = t.length[i]
        x[i] = x[t.parent[i]] + (haslen ? (isnan(l) ? 0.0 : max(l, 0.0)) : 1.0)
    end
    return x
end

# number of edges from each node to its deepest tip
function nodeheight_steps(t::PhyloTree)
    h = zeros(Int, nnodes(t))
    for i in postorder(t)
        isleaf(t, i) && continue
        h[i] = 1 + maximum(h[c] for c in t.children[i])
    end
    return h
end

"""
    treeheight(tree)

Largest root-to-tip distance.
"""
treeheight(t::PhyloTree) = maximum(rootdistance(t))

"""
    ntipsbelow(tree)

Number of tips below each node (1 for a tip).
"""
function ntipsbelow(t::PhyloTree)
    k = zeros(Int, nnodes(t))
    for i in postorder(t)
        k[i] = isleaf(t, i) ? 1 : sum(k[c] for c in t.children[i])
    end
    return k
end

"""
    ladderize!(tree; right=true) -> tree

Sort every node's children by size so that larger clades are drawn last
(`right = true`, the "ladder" descends to the bottom/clockwise) or first.
"""
function ladderize!(t::PhyloTree; right::Bool=true)
    k = ntipsbelow(t)
    for i in 1:nnodes(t)
        sort!(t.children[i]; by=c -> k[c], rev=!right)
    end
    return t
end

"""
    rotatenode!(tree, node)

Reverse the order of a node's children.
"""
function rotatenode!(t::PhyloTree, node)
    reverse!(t.children[nodeindex(t, node)])
    return t
end

"""
    sorttips!(tree, order) -> tree

Rotate nodes so that tips come out as close as possible to `order` (a vector
of tip labels): each node's children are sorted by the mean rank of their tips.
"""
function sorttips!(t::PhyloTree, order::AbstractVector)
    rank = Dict(String(o) => r for (r, o) in enumerate(order))
    score = zeros(nnodes(t))
    cnt = zeros(nnodes(t))
    for i in postorder(t)
        if isleaf(t, i)
            score[i] = get(rank, t.label[i], length(order) + 1)
            cnt[i] = 1
        else
            score[i] = sum(score[c] * cnt[c] for c in t.children[i])
            cnt[i] = sum(cnt[c] for c in t.children[i])
            score[i] /= cnt[i]
        end
    end
    for i in 1:nnodes(t)
        sort!(t.children[i]; by=c -> score[c])
    end
    return t
end

function Base.copy(t::PhyloTree)
    PhyloTree(copy(t.parent), [copy(c) for c in t.children], copy(t.length), copy(t.label),
              [copy(d) for d in t.data], t.root)
end

"""
    keeptips(tree, labels) -> PhyloTree

A new tree pruned to the tips in `labels`; nodes left with one child are
removed and their branch lengths merged.
"""
function keeptips(t::PhyloTree, labels)
    keep = Set(nodeindex(t, l) for l in labels)
    k = zeros(Int, nnodes(t))
    for i in postorder(t)
        k[i] = isleaf(t, i) ? (i in keep ? 1 : 0) : sum(k[c] for c in t.children[i])
    end
    k[t.root] == 0 && throw(ArgumentError("no tips kept"))
    out = PhyloTree()
    function build(i, parent, extra)
        kids = filter(c -> k[c] > 0, t.children[i])
        len = (isnan(t.length[i]) ? 0.0 : t.length[i]) + extra
        if length(kids) == 1
            return build(kids[1], parent, parent == 0 ? 0.0 : len)
        end
        j = addnode!(out; parent, length=(parent == 0 ? t.length[i] : len), label=t.label[i])
        out.data[j] = copy(t.data[i])
        for c in kids
            build(c, j, 0.0)
        end
        return j
    end
    build(t.root, 0, 0.0)
    return out
end

"""
    reroot(tree, outgroup) -> PhyloTree

A new tree rooted on the branch above `outgroup` (a node, a label or a
collection of labels whose MRCA is used), splitting that branch in half.
"""
function reroot(t::PhyloTree, outgroup)
    o = nodeindex(t, outgroup)
    o == t.root && return copy(t)
    # undirected adjacency with lengths and data carried on the child end
    n = nnodes(t)
    adj = [Int[] for _ in 1:n]
    for i in 1:n
        p = t.parent[i]
        p == 0 && continue
        push!(adj[i], p)
        push!(adj[p], i)
    end
    elen(a, b) = t.parent[a] == b ? t.length[a] : t.length[b]
    edata(a, b) = t.parent[a] == b ? t.data[a] : t.data[b]
    out = PhyloTree()
    r = addnode!(out)
    L = t.length[o]
    half = isnan(L) ? NaN : L / 2
    p = t.parent[o]
    function build(i, from, parent, len, data)
        # skip the old root when it would have one child
        nbrs = filter(!=(from), adj[i])
        if i == t.root && length(nbrs) == 1
            nxt = nbrs[1]
            l2 = elen(i, nxt)
            return build(nxt, i, parent, (isnan(len) ? 0.0 : len) + (isnan(l2) ? 0.0 : l2), data)
        end
        j = addnode!(out; parent, length=len, label=t.label[i])
        for (k, v) in data
            k === :support && continue
            out.data[j][k] = v
        end
        haskey(data, :support) && (out.data[j][:support] = data[:support])
        for c in nbrs
            build(c, i, j, elen(i, c), edata(i, c))
        end
        return j
    end
    build(o, p, r, half, t.data[o])
    build(p, o, r, half, t.data[o])
    return out
end

function Base.show(io::IO, t::PhyloTree)
    print(io, "PhyloTree(", ntips(t), " tips, ", nnodes(t), " nodes)")
end

function Base.show(io::IO, ::MIME"text/plain", t::PhyloTree)
    n = ntips(t)
    print(io, "PhyloTree with ", n, " tips and ", nnodes(t), " nodes")
    names = tipnames(t)
    if n > 0
        shown = n <= 8 ? names : vcat(names[1:4], ["…"], names[end-2:end])
        print(io, "\n  tips: ", join(shown, ", "))
    end
    haslen = any(!isnan, t.length)
    print(io, "\n  branch lengths: ", haslen ? "yes (height $(round(treeheight(t); sigdigits=4)))" : "no")
    keys_ = unique!(sort!(collect(Iterators.flatten(keys.(t.data)))))
    isempty(keys_) || print(io, "\n  annotations: ", join(keys_, ", "))
end
