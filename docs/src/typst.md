# CeTZ / Typst

Saving to `.typ` with `standalone=false` writes Typst code that draws the figure
with [CeTZ](https://typst.app/universe/package/cetz), to `#include` in a Typst
document. Without `standalone=false` the file compiles on its own.

```julia
using PlotPhyloTree, Random
tree = randtree(30; rng=Xoshiro(1), labels=["Species_$i" for i in 1:30])
ladderize!(tree)
p = treeplot(tree; layout=:circular, italic=true)
highlight!(p, childnodes(tree, rootnode(tree))[1]; label="Clade A")
timescale!(p)
savefig("tree.typ", p; standalone=false, scale=0.8)
```

`main.typ`:

```typst
#set page(width: 16cm, height: auto)

#figure(
  include "tree.typ",
  caption: [A phylogeny.],
)
```

`typst compile main.typ`:

![CeTZ output](assets/typst.png)

[`cetzstring`](@ref) returns the code as a string. The default CeTZ version
needs Typst ≥ 0.13.1; for older Typst pass e.g. `cetz="0.3.0"` (Typst ≥ 0.11).
`scale` multiplies all lengths and `font` sets the label font.
