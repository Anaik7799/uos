(* HW.4.2.1 / HW.4.2.2 / HW.4.2.3 — the graph kernels, ported from the
   imported ZK calculators (zk_page_rank_calculator.ml,
   zk_graph_betweenness_calculator.ml — the R14 mirrors) onto the model's
   own link graph. Every kernel is DETERMINISTIC by construction: nodes
   sorted by slug, edges deduplicated and sorted, summation in fixed
   order, ties by slug. A ranking that is not a function of the corpus
   would make the digest gate report meaningless drift. *)

type g

(* nodes = pages sorted by slug; edges = outlinks that resolve to pages,
   deduplicated, self-loops dropped. Input order CANNOT matter. *)
val of_model : Hermes_wiki.model -> g

val nodes : g -> string list
val edge_count : g -> int

(* Personalized PageRank by bounded power iteration (d=0.85, <=200
   rounds, L1 delta 1e-9; dangling mass redistributed to the teleport).
   seeds=[] means uniform teleport. Returns EVERY node, rank descending,
   ties slug-ascending; the ranks sum to 1 (within 1e-6). *)
val pagerank : ?seeds:string list -> g -> (string * float) list

(* Brandes 2001 over the directed graph, fixed vertex order. Every node,
   score descending, ties slug-ascending. *)
val betweenness : g -> (string * float) list

(* Constrained label propagation (HW.4.2.2): labels initialised to own
   slug, sweep in slug order over UNDIRECTED neighbourhoods, ties to the
   smallest label, bounded rounds. Communities keyed by their smallest
   member slug, members sorted; communities(shuffle g) = communities(g)
   by construction. *)
val communities : g -> (string * string list) list

(* Orphans: nodes with no inbound edge, sorted — the audit gauge. *)
val orphans : g -> string list

(* Eccentricity from a node: the longest BFS distance to any REACHABLE
   node (unreachable pages are the orphans gauge's business). None when
   the node is not in the graph. *)
val ecc_from : g -> string -> int option
