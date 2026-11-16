# TikZ / LaTeX

Saving to `.tikz` writes a `tikzpicture` to `\input` into a LaTeX document.
Labels are typeset by LaTeX in the document's font. Saving to `.tex` writes a
standalone document instead.

```julia
using PlotPhyloTree, Random
tree = randtree(30; rng=Xoshiro(1), labels=["Species_$i" for i in 1:30])
ladderize!(tree)
p = treeplot(tree; layout=:circular, italic=true)
highlight!(p, childnodes(tree, rootnode(tree))[1]; label="Clade A")
timescale!(p)
savefig("tree.tikz", p)
```

`main.tex`:

```latex
\documentclass{article}
\usepackage{tikz}
\usepackage{graphicx}
\begin{document}

\begin{figure}
  \centering
  \resizebox{0.8\linewidth}{!}{\input{tree.tikz}}
  \caption{A phylogeny.}
\end{figure}

\end{document}
```

`pdflatex main.tex`:

![TikZ output](assets/tikz.png)

[`tikzstring`](@ref) returns the code as a string; `scale` multiplies all
lengths and `font` sets the label font (e.g. `font="\\rmfamily"`). Images
added with [`tipimages!`](@ref) are written next to the `.tikz` file.
