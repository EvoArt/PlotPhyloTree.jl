# Newick / NHX / BEAST-annotated Newick, and the trees block of Nexus files.

"""
    parsenewick(str) -> PhyloTree

Parse one tree in Newick format. Handles quoted labels, branch lengths,
numeric internal labels (stored as the `:support` annotation),
`[&&NHX:key=value:...]` comments and BEAST/MrBayes-style
`[&key=value,key={a,b}]` comments (stored as node annotations; numbers are
parsed, `{a,b}` becomes a vector).
"""
function parsenewick(str::AbstractString)
    trees = _parse_newicks(String(str); first_only=true)
    isempty(trees) && throw(ArgumentError("no tree found"))
    return trees[1]
end

"""
    readnewick(path) -> PhyloTree
    readnewick(path; all=true) -> Vector{PhyloTree}

Read the first tree (or all trees) from a Newick file. Use
[`parsenewick`](@ref) for a string.
"""
function readnewick(path::AbstractString; all::Bool=false)
    s = read(path, String)
    trees = _parse_newicks(s; first_only=!all)
    isempty(trees) && throw(ArgumentError("no tree found in $path"))
    return all ? trees : trees[1]
end
readnewick(io::IO; all::Bool=false) = (tr = _parse_newicks(read(io, String); first_only=!all); all ? tr : tr[1])

mutable struct _NewickParser
    s::String
    i::Int
end

_peek(p::_NewickParser) = p.i <= ncodeunits(p.s) ? p.s[p.i] : '\0'
_advance!(p::_NewickParser) = (p.i = nextind(p.s, p.i))

function _skipws!(p::_NewickParser)
    while p.i <= ncodeunits(p.s) && isspace(p.s[p.i])
        _advance!(p)
    end
end

function _parse_newicks(s::String; first_only::Bool=false)
    p = _NewickParser(s, 1)
    trees = PhyloTree[]
    while true
        _skipws!(p)
        # skip leading comments such as [&R] or [&U]
        while _peek(p) == '['
            _read_comment!(p)
            _skipws!(p)
        end
        p.i > ncodeunits(s) && break
        t = PhyloTree()
        _parse_subtree!(p, t, 0)
        _skipws!(p)
        if _peek(p) == ';'
            _advance!(p)
        elseif p.i <= ncodeunits(s)
            throw(ArgumentError("unexpected character '$(_peek(p))' at position $(p.i) in Newick string"))
        end
        push!(trees, t)
        first_only && break
    end
    return trees
end

function _read_comment!(p::_NewickParser)
    @assert _peek(p) == '['
    _advance!(p)
    start = p.i
    depth = 1
    while p.i <= ncodeunits(p.s)
        c = p.s[p.i]
        if c == '['
            depth += 1
        elseif c == ']'
            depth -= 1
            if depth == 0
                str = p.s[start:prevind(p.s, p.i)]
                _advance!(p)
                return str
            end
        end
        _advance!(p)
    end
    throw(ArgumentError("unterminated comment in Newick string"))
end

function _read_label!(p::_NewickParser)
    _skipws!(p)
    c = _peek(p)
    if c == '\'' || c == '"'
        q = c
        _advance!(p)
        buf = IOBuffer()
        while true
            p.i > ncodeunits(p.s) && throw(ArgumentError("unterminated quoted label"))
            d = p.s[p.i]
            _advance!(p)
            if d == q
                if _peek(p) == q          # '' escapes a quote
                    print(buf, q)
                    _advance!(p)
                else
                    break
                end
            else
                print(buf, d)
            end
        end
        return String(take!(buf)), true
    end
    start = p.i
    while p.i <= ncodeunits(p.s)
        d = p.s[p.i]
        (d in "(),:;[" || d == '\n' || d == '\r' || d == '\t') && break
        _advance!(p)
    end
    return strip(p.s[start:prevind(p.s, p.i)]), false
end

function _parse_subtree!(p::_NewickParser, t::PhyloTree, parent::Int)
    node = addnode!(t; parent)
    _skipws!(p)
    if _peek(p) == '('
        _advance!(p)
        while true
            _parse_subtree!(p, t, node)
            _skipws!(p)
            c = _peek(p)
            if c == ','
                _advance!(p)
            elseif c == ')'
                _advance!(p)
                break
            else
                throw(ArgumentError("expected ',' or ')' at position $(p.i), found '$c'"))
            end
        end
    end
    # label, comments, length, comments in any reasonable order
    label, quoted = _read_label!(p)
    while true
        _skipws!(p)
        c = _peek(p)
        if c == '['
            _apply_comment!(t, node, _read_comment!(p))
        elseif c == ':'
            _advance!(p)
            _skipws!(p)
            while _peek(p) == '['
                _apply_comment!(t, node, _read_comment!(p))
                _skipws!(p)
            end
            start = p.i
            while p.i <= ncodeunits(p.s) && !(p.s[p.i] in "(),;[: \t\n\r")
                _advance!(p)
            end
            numstr = p.s[start:prevind(p.s, p.i)]
            v = tryparse(Float64, numstr)
            v === nothing && throw(ArgumentError("bad branch length \"$numstr\""))
            t.length[node] = v
        else
            break
        end
    end
    if !isleaf(t, node) && !quoted && !isempty(label)
        # numeric internal labels are support values; "90/0.95" keeps the first
        parts = split(label, '/')
        v = tryparse(Float64, parts[1])
        if v !== nothing
            t.data[node][:support] = v
            if length(parts) > 1
                vs = [tryparse(Float64, q) for q in parts]
                all(!isnothing, vs) && (t.data[node][:supports] = Float64.(vs))
            end
            label = ""
        end
    end
    t.label[node] = label
    return node
end

function _apply_comment!(t::PhyloTree, node::Int, c::AbstractString)
    c = strip(c)
    if startswith(c, "&&NHX")
        for kv in split(c[6:end], ':'; keepempty=false)
            k, v = _splitkv(kv)
            k === nothing || (t.data[node][k] = _annotation_value(v))
        end
    elseif startswith(c, '&')
        for kv in _split_top(c[2:end], ',')
            k, v = _splitkv(kv)
            k === nothing || (t.data[node][k] = _annotation_value(v))
        end
    else
        t.data[node][:comment] = String(c)
    end
    return nothing
end

function _splitkv(kv::AbstractString)
    j = findfirst('=', kv)
    j === nothing && return nothing, nothing
    k = strip(kv[1:j-1])
    isempty(k) && return nothing, nothing
    return Symbol(k), strip(kv[j+1:end])
end

# split on `sep` outside of braces/quotes
function _split_top(s::AbstractString, sep::Char)
    out = String[]
    depth = 0
    inq = false
    buf = IOBuffer()
    for ch in s
        if ch == '"'
            inq = !inq
        elseif !inq && ch == '{'
            depth += 1
        elseif !inq && ch == '}'
            depth -= 1
        end
        if ch == sep && depth == 0 && !inq
            push!(out, String(take!(buf)))
        else
            print(buf, ch)
        end
    end
    push!(out, String(take!(buf)))
    return filter!(!isempty ∘ strip, out)
end

function _annotation_value(v::AbstractString)
    v = strip(v)
    if startswith(v, '{') && endswith(v, '}')
        parts = _split_top(v[2:end-1], ',')
        vals = [_annotation_value(q) for q in parts]
        return all(x -> x isa Real, vals) ? Float64.(vals) : vals
    end
    if length(v) >= 2 && v[1] == '"' && v[end] == '"'
        return String(v[2:end-1])
    end
    x = tryparse(Float64, v)
    x === nothing || return x
    return String(v)
end

# --- writing -------------------------------------------------------------

"""
    writenewick(tree; digits=6, support=true) -> String
    writenewick(path, tree; kwargs...)

Newick representation of `tree`. Support values (the `:support` annotation)
are written as internal labels when `support = true`.
"""
function writenewick(t::PhyloTree; digits::Integer=6, support::Bool=true)
    io = IOBuffer()
    _write_node(io, t, t.root, digits, support)
    print(io, ';')
    return String(take!(io))
end

function writenewick(path::AbstractString, t::PhyloTree; kwargs...)
    open(io -> println(io, writenewick(t; kwargs...)), path, "w")
    return path
end

function _write_node(io, t, i, digits, support)
    ch = t.children[i]
    if !isempty(ch)
        print(io, '(')
        for (k, c) in enumerate(ch)
            k > 1 && print(io, ',')
            _write_node(io, t, c, digits, support)
        end
        print(io, ')')
    end
    lab = t.label[i]
    if isempty(lab) && support && !isleaf(t, i) && haskey(t.data[i], :support)
        s = t.data[i][:support]
        s isa Real ? _printnum(io, s) : print(io, s)
    elseif !isempty(lab)
        if occursin(r"[\s(),:;\[\]']", lab)
            print(io, '\'', replace(lab, "'" => "''"), '\'')
        else
            print(io, lab)
        end
    end
    l = t.length[i]
    isnan(l) || (print(io, ':'); _printnum(io, round(l; sigdigits=digits)))
end

# --- Nexus ---------------------------------------------------------------

"""
    readnexus(path; all=false) -> PhyloTree (or Vector{PhyloTree})

Read trees from the `TREES` block of a Nexus file (as written by BEAST,
MrBayes, RevBayes, FigTree, ...), applying any `TRANSLATE` table. Node
annotations in `[&...]` comments are kept.
"""
function readnexus(path::AbstractString; all::Bool=false)
    s = read(path, String)
    trees = _parse_nexus(s)
    isempty(trees) && throw(ArgumentError("no trees block found in $path"))
    return all ? trees : trees[1]
end

function _parse_nexus(s::String)
    m = match(r"begin\s+trees\s*;"i, s)
    m === nothing && return PhyloTree[]
    body = s[m.offset+length(m.match):end]
    e = match(r"\bend\s*;"i, body)
    e === nothing || (body = body[1:e.offset-1])
    translate = Dict{String,String}()
    tm = match(r"translate\s+(.*?);"is, body)
    if tm !== nothing
        for entry in split(tm.captures[1], ',')
            parts = split(strip(entry); limit=2)
            length(parts) == 2 || continue
            translate[strip(parts[1])] = strip(strip(parts[2]), ['\'', '"'])
        end
    end
    trees = PhyloTree[]
    for tm2 in eachmatch(r"tree\s+[^=]+=\s*(.*?;)"is, body)
        t = _parse_newicks(String(tm2.captures[1]); first_only=true)[1]
        if !isempty(translate)
            for i in 1:nnodes(t)
                lab = t.label[i]
                haskey(translate, lab) && (t.label[i] = translate[lab])
            end
        end
        push!(trees, t)
    end
    return trees
end

_printnum(io, x::Real) = isinteger(x) && abs(x) < 1e15 ? print(io, Int(x)) : print(io, x)
