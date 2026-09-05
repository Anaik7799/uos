(* HW.6.3.1 / HW.6.3.2 — full-text search with block-level hits.

   Deterministic BY LAW: the index is a sorted structure, ranking is
   score-descending with slug ties, and offline equals online — a search
   through the index returns exactly what a naive scan of the corpus
   returns (the differential the tests pin). The index digest is one
   canonical serialisation, so the whole index is pinnable (P1).

   Block hits (HW.6.3.2): every hit names a ^id block anchor — a hit
   that cannot be addressed is not returned. Fences are excluded from
   tokenisation (the similarity row's convention). *)

type index

val build : Hermes_wiki.model -> index

(* sha256 of the canonical serialisation — pinnable, drift-visible. *)
val digest : index -> string

(* tokens of a query: lowercase alnum runs, length >= 2 *)
val tokens : string -> string list

(* page hits: score descending (sum of term counts, title 3x), ties by
   slug ascending. Every scored page contains EVERY query token. *)
val search : index -> string -> (string * int) list

(* block hits: (slug, ^id) for every ^id-anchored block whose text
   contains every query token. Sorted by slug then id. *)
val block_hits : index -> string -> (string * string) list
