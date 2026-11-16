# Coordinate systems. Every layer works in "tree coordinates" (r, pos):
#   r   — distance from the root along the depth axis, in pixels
#   pos — position across the tips; tip k sits at pos = k
# Polar maps pos to an angle and r to a radius; Cartesian maps them to x/y.

abstract type Coord end

struct Polar <: Coord
    φ0::Float64     # angle (radians, clockwise from east) of pos = 0.5
    slot::Float64   # radians per unit of pos
end

struct Cartesian <: Coord
    dir::Symbol     # direction in which depth grows: :right, :left, :down, :up
    sp::Float64     # pixels per unit of pos
end

angle(c::Polar, pos) = c.φ0 + (pos - 0.5) * c.slot

function xy(c::Polar, r, pos)
    a = angle(c, pos)
    return (r * cos(a), r * sin(a))
end

function xy(c::Cartesian, r, pos)
    q = pos * c.sp
    c.dir === :right && return (Float64(r), q)
    c.dir === :left && return (-Float64(r), q)
    c.dir === :down && return (q, Float64(r))
    return (q, -Float64(r))
end

"""Direction (radians, screen) in which depth increases at `pos`."""
outangle(c::Polar, pos) = angle(c, pos)
outangle(c::Cartesian, pos) = c.dir === :right ? 0.0 : c.dir === :left ? Float64(π) :
                              c.dir === :down ? π / 2 : -π / 2

"""Pixels per unit of pos at depth `r` (arc length)."""
pxperpos(c::Polar, r) = max(r, 1e-9) * c.slot
pxperpos(c::Cartesian, r) = c.sp

ispolar(c::Coord) = c isa Polar

# unit vector along increasing pos at `pos`
function acrossvec(c::Polar, pos)
    a = angle(c, pos)
    return (-sin(a), cos(a))
end
function acrossvec(c::Cartesian, pos)
    c.dir in (:right, :left) && return (0.0, 1.0)
    return (1.0, 0.0)
end

# --- path helpers in tree coordinates -------------------------------------------

move!(pb::PathBuilder, c::Coord, r, pos) = M!(pb, xy(c, r, pos)...)
line!(pb::PathBuilder, c::Coord, r, pos) = L!(pb, xy(c, r, pos)...)

"""Move along pos at constant depth r: an arc in polar, a straight line otherwise."""
function across!(pb::PathBuilder, c::Polar, r, pos1, pos2)
    arc!(pb, 0.0, 0.0, r, angle(c, pos1), angle(c, pos2))
end
across!(pb::PathBuilder, c::Cartesian, r, pos1, pos2) = L!(pb, xy(c, r, pos2)...)

"""Closed region r ∈ [r1, r2], pos ∈ [p1, p2] (an annular sector in polar)."""
function region!(pb::PathBuilder, c::Coord, r1, r2, p1, p2)
    move!(pb, c, r2, p1)
    across!(pb, c, r2, p1, p2)
    if c isa Polar && r1 <= 1e-9
        L!(pb, 0.0, 0.0)
    else
        line!(pb, c, r1, p2)
        across!(pb, c, r1, p2, p1)
    end
    Z!(pb)
    return pb
end

# text placed along the depth axis at `pos`, reading outward and never upside down
function radial_text_params(c::Coord, pos)
    a = outangle(c, pos)
    if cos(a) < -1e-9
        return rad2deg(a + π), :right
    else
        return rad2deg(a), :left
    end
end
