# Regenerates the bundled metric tables in src/fontdata.jl from the OpenType
# fonts in a TeX Live installation (Latin Modern, TeX Gyre Termes).
# Run: julia --project=examples examples/fontdata_gen.jl
using PlotPhyloTree
using PlotPhyloTree: _sfntwidths, _CHARS

font(name) = (p = strip(read(`kpsewhich $name`, String)); isempty(p) ? error("$name not found") : p)

const FONTS = [
    (:lmroman, "Latin Modern Roman", ["lmroman10-regular.otf", "lmroman10-bold.otf", "lmroman10-italic.otf",
                                      "lmroman10-bolditalic.otf"]),
    (:lmsans, "Latin Modern Sans", ["lmsans10-regular.otf", "lmsans10-bold.otf", "lmsans10-oblique.otf",
                                    "lmsans10-boldoblique.otf"]),
    (:times, "Times", ["texgyretermes-regular.otf", "texgyretermes-bold.otf", "texgyretermes-italic.otf",
                       "texgyretermes-bolditalic.otf"]),
]

io = IOBuffer()
println(io, "#= GENERATED =#")
names = String[]
for (key, name, files) in FONTS
    tabs = [_sfntwidths(font(f)) for f in files]
    for (style, t) in zip(("regular", "bold", "italic", "bolditalic"), tabs)
        v = [round(Int, get(t, c, 0.0)) for c in _CHARS]
        println(io, "const _", uppercase(String(key)), "_", uppercase(style), " = Int16[", join(v, ','), "]")
    end
    K = uppercase(String(key))
    push!(names, ":$key => FontMetrics(\"$name\", _unpack(_$(K)_REGULAR), _unpack(_$(K)_BOLD), " *
                 "_unpack(_$(K)_ITALIC), _unpack(_$(K)_BOLDITALIC), $(round(Int, tabs[1]['n'])).0)")
end
println(io, "\nconst BUNDLED_METRICS = Dict{Symbol,FontMetrics}(\n    :helvetica => _helvetica(),")
for n in names
    println(io, "    ", n, ",")
end
println(io, ")")

path = joinpath(@__DIR__, "..", "src", "fontdata.jl")
src = read(path, String)
i = findfirst("#= GENERATED =#", src)
write(path, src[1:first(i)-1] * String(take!(io)))
println("wrote ", path)
