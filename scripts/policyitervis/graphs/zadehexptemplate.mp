verbatimtex
%&latex
\documentclass{article}
\usepackage{amsmath,amssymb}
\begin{document}
etex

input "latex";

input ./metapostgraphs/graphicslib
input ./metapostgraphs/graphlib

input graphs/zadehexpgraph;			

build_graph(true);
