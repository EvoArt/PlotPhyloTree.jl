"""
    PhylogenyIO

A small, dependency-free phylogenetic tree type with readers and writers for
Newick (including NHX and BEAST/MrBayes `[&...]` annotations) and the trees
block of Nexus files, plus the usual tree queries and edits.
"""
module PhylogenyIO

using Random: Random, AbstractRNG, randexp

export PhyloTree, addnode!, nnodes, ntips, isleaf, isroot, parentnode, childnodes, branchlength,
       nodelabel, rootnode, getdata, setdata!, preorder, postorder, tips, tipnames, internalnodes,
       descendants, ancestors, findnode, mrca, nodeindex, rootdistance, treeheight, ntipsbelow,
       ladderize!, rotatenode!, sorttips!, keeptips, reroot,
       parsenewick, readnewick, writenewick, readnexus, randtree

include("tree.jl")
include("newick.jl")
include("simulate.jl")

end
