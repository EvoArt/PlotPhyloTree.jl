# Colours: parsing, mixing, palettes and colour maps.

struct RGBA
    r::Float64
    g::Float64
    b::Float64
    a::Float64
end

const TRANSPARENT = RGBA(0, 0, 0, 0)

const CSS = Dict{String,UInt32}(
    "aliceblue" => 0xF0F8FF, "antiquewhite" => 0xFAEBD7, "aqua" => 0x00FFFF, "aquamarine" => 0x7FFFD4,
    "azure" => 0xF0FFFF, "beige" => 0xF5F5DC, "bisque" => 0xFFE4C4, "black" => 0x000000,
    "blanchedalmond" => 0xFFEBCD, "blue" => 0x0000FF, "blueviolet" => 0x8A2BE2, "brown" => 0xA52A2A,
    "burlywood" => 0xDEB887, "cadetblue" => 0x5F9EA0, "chartreuse" => 0x7FFF00, "chocolate" => 0xD2691E,
    "coral" => 0xFF7F50, "cornflowerblue" => 0x6495ED, "cornsilk" => 0xFFF8DC, "crimson" => 0xDC143C,
    "cyan" => 0x00FFFF, "darkblue" => 0x00008B, "darkcyan" => 0x008B8B, "darkgoldenrod" => 0xB8860B,
    "darkgray" => 0xA9A9A9, "darkgreen" => 0x006400, "darkgrey" => 0xA9A9A9, "darkkhaki" => 0xBDB76B,
    "darkmagenta" => 0x8B008B, "darkolivegreen" => 0x556B2F, "darkorange" => 0xFF8C00,
    "darkorchid" => 0x9932CC, "darkred" => 0x8B0000, "darksalmon" => 0xE9967A, "darkseagreen" => 0x8FBC8F,
    "darkslateblue" => 0x483D8B, "darkslategray" => 0x2F4F4F, "darkslategrey" => 0x2F4F4F,
    "darkturquoise" => 0x00CED1, "darkviolet" => 0x9400D3, "deeppink" => 0xFF1493,
    "deepskyblue" => 0x00BFFF, "dimgray" => 0x696969, "dimgrey" => 0x696969, "dodgerblue" => 0x1E90FF,
    "firebrick" => 0xB22222, "floralwhite" => 0xFFFAF0, "forestgreen" => 0x228B22, "fuchsia" => 0xFF00FF,
    "gainsboro" => 0xDCDCDC, "ghostwhite" => 0xF8F8FF, "gold" => 0xFFD700, "goldenrod" => 0xDAA520,
    "gray" => 0x808080, "grey" => 0x808080, "green" => 0x008000, "greenyellow" => 0xADFF2F,
    "honeydew" => 0xF0FFF0, "hotpink" => 0xFF69B4, "indianred" => 0xCD5C5C, "indigo" => 0x4B0082,
    "ivory" => 0xFFFFF0, "khaki" => 0xF0E68C, "lavender" => 0xE6E6FA, "lavenderblush" => 0xFFF0F5,
    "lawngreen" => 0x7CFC00, "lemonchiffon" => 0xFFFACD, "lightblue" => 0xADD8E6, "lightcoral" => 0xF08080,
    "lightcyan" => 0xE0FFFF, "lightgoldenrodyellow" => 0xFAFAD2, "lightgray" => 0xD3D3D3,
    "lightgreen" => 0x90EE90, "lightgrey" => 0xD3D3D3, "lightpink" => 0xFFB6C1, "lightsalmon" => 0xFFA07A,
    "lightseagreen" => 0x20B2AA, "lightskyblue" => 0x87CEFA, "lightslategray" => 0x778899,
    "lightslategrey" => 0x778899, "lightsteelblue" => 0xB0C4DE, "lightyellow" => 0xFFFFE0,
    "lime" => 0x00FF00, "limegreen" => 0x32CD32, "linen" => 0xFAF0E6, "magenta" => 0xFF00FF,
    "maroon" => 0x800000, "mediumaquamarine" => 0x66CDAA, "mediumblue" => 0x0000CD,
    "mediumorchid" => 0xBA55D3, "mediumpurple" => 0x9370DB, "mediumseagreen" => 0x3CB371,
    "mediumslateblue" => 0x7B68EE, "mediumspringgreen" => 0x00FA9A, "mediumturquoise" => 0x48D1CC,
    "mediumvioletred" => 0xC71585, "midnightblue" => 0x191970, "mintcream" => 0xF5FFFA,
    "mistyrose" => 0xFFE4E1, "moccasin" => 0xFFE4B5, "navajowhite" => 0xFFDEAD, "navy" => 0x000080,
    "oldlace" => 0xFDF5E6, "olive" => 0x808000, "olivedrab" => 0x6B8E23, "orange" => 0xFFA500,
    "orangered" => 0xFF4500, "orchid" => 0xDA70D6, "palegoldenrod" => 0xEEE8AA, "palegreen" => 0x98FB98,
    "paleturquoise" => 0xAFEEEE, "palevioletred" => 0xDB7093, "papayawhip" => 0xFFEFD5,
    "peachpuff" => 0xFFDAB9, "peru" => 0xCD853F, "pink" => 0xFFC0CB, "plum" => 0xDDA0DD,
    "powderblue" => 0xB0E0E6, "purple" => 0x800080, "rebeccapurple" => 0x663399, "red" => 0xFF0000,
    "rosybrown" => 0xBC8F8F, "royalblue" => 0x4169E1, "saddlebrown" => 0x8B4513, "salmon" => 0xFA8072,
    "sandybrown" => 0xF4A460, "seagreen" => 0x2E8B57, "seashell" => 0xFFF5EE, "sienna" => 0xA0522D,
    "silver" => 0xC0C0C0, "skyblue" => 0x87CEEB, "slateblue" => 0x6A5ACD, "slategray" => 0x708090,
    "slategrey" => 0x708090, "snow" => 0xFFFAFA, "springgreen" => 0x00FF7F, "steelblue" => 0x4682B4,
    "tan" => 0xD2B48C, "teal" => 0x008080, "thistle" => 0xD8BFD8, "tomato" => 0xFF6347,
    "turquoise" => 0x40E0D0, "violet" => 0xEE82EE, "wheat" => 0xF5DEB3, "white" => 0xFFFFFF,
    "whitesmoke" => 0xF5F5F5, "yellow" => 0xFFFF00, "yellowgreen" => 0x9ACD32,
)

_fromhex(u::UInt32, a=1.0) = RGBA(((u >> 16) & 0xff) / 255, ((u >> 8) & 0xff) / 255, (u & 0xff) / 255, a)

"""
    tocolor(c) -> RGBA

Interpret a colour: a CSS name (`:steelblue`, `"tomato"`), `:grayNN`, a hex
string (`"#1b9e77"`, `"#1b9e7780"`, `"#abc"`), an `(r, g, b)` or
`(r, g, b, a)` tuple with values in 0–1, a `(colour, alpha)` tuple, an
integer index into the default palette, `nothing`/`:none`/`:transparent`, or
any colour object with `r`, `g`, `b` (and optionally `alpha`) fields, such as
Colors.jl's `RGB`.
"""
tocolor(c::RGBA) = c
tocolor(::Nothing) = TRANSPARENT
tocolor(c::Symbol) = tocolor(String(c))
tocolor(c::Integer) = tocolor(PALETTES[:default][mod1(c, length(PALETTES[:default]))])
function tocolor(s::AbstractString)
    s = lowercase(strip(s))
    (s == "none" || s == "transparent" || isempty(s)) && return TRANSPARENT
    if startswith(s, '#')
        h = s[2:end]
        if length(h) == 3 || length(h) == 4
            h = join(ch^2 for ch in h)
        end
        if length(h) == 6
            return _fromhex(parse(UInt32, h; base=16))
        elseif length(h) == 8
            u = parse(UInt32, h; base=16)
            return _fromhex(u >> 8, (u & 0xff) / 255)
        end
        throw(ArgumentError("bad hex colour \"$s\""))
    end
    m = match(r"^gr[ae]y(\d{1,3})$", s)
    if m !== nothing
        v = parse(Int, m.captures[1]) / 100
        return RGBA(v, v, v, 1)
    end
    haskey(CSS, s) && return _fromhex(CSS[s])
    throw(ArgumentError("unknown colour \"$s\""))
end
tocolor(c::Tuple{Any,Real}) = (k = tocolor(c[1]); RGBA(k.r, k.g, k.b, k.a * c[2]))
tocolor(c::NTuple{3,Real}) = RGBA(c[1], c[2], c[3], 1)
tocolor(c::NTuple{4,Real}) = RGBA(c[1], c[2], c[3], c[4])
function tocolor(c)
    if hasproperty(c, :r) && hasproperty(c, :g) && hasproperty(c, :b)
        a = hasproperty(c, :alpha) ? Float64(getproperty(c, :alpha)) : 1.0
        return RGBA(Float64(c.r), Float64(c.g), Float64(c.b), a)
    end
    throw(ArgumentError("cannot interpret $(repr(c)) as a colour"))
end

isvisible(c::RGBA) = c.a > 0

_byte(v) = round(Int, 255 * clamp(v, 0.0, 1.0))
hexcolor(c::RGBA) = string('#', string(_byte(c.r); base=16, pad=2), string(_byte(c.g); base=16, pad=2),
                           string(_byte(c.b); base=16, pad=2))

withalpha(c, a::Real) = (k = tocolor(c); RGBA(k.r, k.g, k.b, Float64(a)))

"""    mix(a, b, t)  linear blend of colours `a` and `b` (`t = 0` gives `a`)."""
function mix(a, b, t::Real)
    x = tocolor(a); y = tocolor(b)
    RGBA(x.r + t * (y.r - x.r), x.g + t * (y.g - x.g), x.b + t * (y.b - x.b), x.a + t * (y.a - x.a))
end

"""    lighten(c, t=0.5)  blend `c` towards white."""
lighten(c, t::Real=0.5) = (k = tocolor(c); m = mix(k, RGBA(1, 1, 1, k.a), t); m)
"""    darken(c, t=0.3)  blend `c` towards black."""
darken(c, t::Real=0.3) = (k = tocolor(c); mix(k, RGBA(0, 0, 0, k.a), t))

luminance(c::RGBA) = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

# --- palettes --------------------------------------------------------------

const PALETTES = Dict{Symbol,Vector{String}}(
    # a clean categorical set (Tableau 10 / Vega), the default
    :default => ["#4E79A7", "#F28E2B", "#59A14F", "#E15759", "#B07AA1", "#EDC948", "#76B7B2",
                 "#FF9DA7", "#9C755F", "#BAB0AC"],
    :okabeito => ["#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7", "#000000"],
    :wong => ["#0072B2", "#E69F00", "#009E73", "#CC79A7", "#56B4E9", "#D55E00", "#F0E442"],
    # soft hues that work as large shaded areas behind a tree
    :pastel => ["#C9B6E4", "#F6E3A1", "#B9E3C6", "#AFC8F2", "#F4B6B6", "#F7CBA4", "#A8DCDC", "#E3C1D9",
                "#D7C9AA", "#CFCFCF"],
    # deeper hues for clade bars, labels and points
    :bold => ["#7B4FA3", "#D8A21B", "#3A9B5C", "#2F6FD0", "#D64545", "#E07B2A", "#2A9D9D", "#B5508A",
              "#8C6D46", "#666666"],
    :tol => ["#332288", "#88CCEE", "#44AA99", "#117733", "#999933", "#DDCC77", "#CC6677", "#882255", "#AA4499"],
    :set2 => ["#66C2A5", "#FC8D62", "#8DA0CB", "#E78AC3", "#A6D854", "#FFD92F", "#E5C494", "#B3B3B3"],
    :dark2 => ["#1B9E77", "#D95F02", "#7570B3", "#E7298A", "#66A61E", "#E6AB02", "#A6761D", "#666666"],
)

"""
    palette(name=:default) -> Vector{RGBA}
    palette(name, n)

Named categorical palettes: `:default` (Tableau 10), `:okabeito`, `:wong`,
`:tol`, `:set2`, `:dark2`, `:pastel` (soft fills) and `:bold` (the matching
strong hues). With `n`, the palette is cycled or truncated to length `n`.
"""
palette(name::Symbol=:default) = tocolor.(PALETTES[name])
palette(name::Symbol, n::Integer) = (p = palette(name); [p[mod1(i, length(p))] for i in 1:n])
palette(v::AbstractVector) = tocolor.(v)
palette(v::AbstractVector, n::Integer) = (p = palette(v); [p[mod1(i, length(p))] for i in 1:n])

# --- colour maps -------------------------------------------------------------

const COLORMAPS = Dict{Symbol,Vector{String}}(
    :viridis => ["#440154", "#482878", "#3E4989", "#31688E", "#26828E", "#1F9E89", "#35B779", "#6ECE58",
                 "#B5DE2B", "#FDE725"],
    :magma => ["#000004", "#180F3D", "#440F76", "#721F81", "#9E2F7F", "#CD4071", "#F1605D", "#FD9668",
               "#FECA8D", "#FCFDBF"],
    :inferno => ["#000004", "#1B0C41", "#4A0C6B", "#781C6D", "#A52C60", "#CF4446", "#ED6925", "#FB9B06",
                 "#F7D13D", "#FCFFA4"],
    :plasma => ["#0D0887", "#46039F", "#7201A8", "#9C179E", "#BD3786", "#D8576B", "#ED7953", "#FB9F3A",
                "#FDCA26", "#F0F921"],
    :cividis => ["#00224E", "#123570", "#3B496C", "#575D6D", "#707173", "#8A8678", "#A59C74", "#C3B369",
                 "#E1CC55", "#FEE838"],
    :rdbu => ["#67001F", "#B2182B", "#D6604D", "#F4A582", "#FDDBC7", "#F7F7F7", "#D1E5F0", "#92C5DE",
              "#4393C3", "#2166AC", "#053061"],
    :spectral => ["#9E0142", "#D53E4F", "#F46D43", "#FDAE61", "#FEE08B", "#FFFFBF", "#E6F598", "#ABDDA4",
                  "#66C2A5", "#3288BD", "#5E4FA2"],
    :blues => ["#F7FBFF", "#DEEBF7", "#C6DBEF", "#9ECAE1", "#6BAED6", "#4292C6", "#2171B5", "#08519C",
               "#08306B"],
    :reds => ["#FFF5F0", "#FEE0D2", "#FCBBA1", "#FC9272", "#FB6A4A", "#EF3B2C", "#CB181D", "#A50F15",
              "#67000D"],
    :greens => ["#F7FCF5", "#E5F5E0", "#C7E9C0", "#A1D99B", "#74C476", "#41AB5D", "#238B45", "#006D2C",
                "#00441B"],
    :ylgnbu => ["#FFFFD9", "#EDF8B1", "#C7E9B4", "#7FCDBB", "#41B6C4", "#1D91C0", "#225EA8", "#253494",
                "#081D58"],
    :ylorrd => ["#FFFFCC", "#FFEDA0", "#FED976", "#FEB24C", "#FD8D3C", "#FC4E2A", "#E31A1C", "#BD0026",
                "#800026"],
    :puor => ["#2D004B", "#542788", "#8073AC", "#B2ABD2", "#D8DAEB", "#F7F7F7", "#FEE0B6", "#FDB863",
              "#E08214", "#B35806", "#7F3B08"],
    :coolwarm => ["#3B4CC0", "#6282EA", "#8DB0FE", "#B8D0F9", "#DDDDDD", "#F5C4AD", "#F49A7B", "#DE604D",
                  "#B40426"],
    :turbo => ["#30123B", "#4662D7", "#36AAF9", "#1AE4B6", "#72FE5E", "#C8EF34", "#FABA39", "#F66B19",
               "#CA2A04", "#7A0403"],
)

"""
    colormap(name)

A colour map: one of `:viridis`, `:magma`, `:inferno`, `:plasma`,
`:cividis`, `:turbo`, `:rdbu`, `:puor`, `:spectral`, `:coolwarm`, `:blues`,
`:reds`, `:greens`, `:ylgnbu`, `:ylorrd`, or a vector of colours to
interpolate. Append `_r` to a name to reverse it (`:viridis_r`).
"""
function colormap(name::Symbol)
    s = String(name)
    if endswith(s, "_r")
        return reverse(colormap(Symbol(s[1:end-2])))
    end
    haskey(COLORMAPS, name) || throw(ArgumentError("unknown colour map :$name; choose from $(sort!(collect(keys(COLORMAPS))))"))
    return tocolor.(COLORMAPS[name])
end
colormap(v::AbstractVector) = tocolor.(v)

"""    cmap(cm, t)  colour at position `t ∈ [0, 1]` of colour map `cm`."""
function cmap(cm::Vector{RGBA}, t::Real)
    isnan(t) && return RGBA(0.75, 0.75, 0.75, 1)
    t = clamp(Float64(t), 0.0, 1.0)
    n = length(cm)
    n == 1 && return cm[1]
    u = t * (n - 1)
    k = min(floor(Int, u), n - 2)
    return mix(cm[k+1], cm[k+2], u - k)
end
cmap(cm, t::Real) = cmap(colormap(cm), t)
