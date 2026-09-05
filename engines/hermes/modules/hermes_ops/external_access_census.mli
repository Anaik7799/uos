type finding = { path : string; line : int; rule : string }
type rule_count = { rule : string; count : int }

val inspect_sources : (string * string) list -> finding list
(** Pure scanner over supplied OCaml source. Strings, quoted strings, character
    literals, and nested comments are opaque. *)

val inspect_tree : root:string -> finding list
(** Controlled read-only filesystem adapter for the complete [.ml]/[.mli]
    denominator below [root]. The adapter returns metadata only. *)

val counts_by_rule : finding list -> rule_count list
(** Deterministic bounded-cardinality control-path metric projection. *)
