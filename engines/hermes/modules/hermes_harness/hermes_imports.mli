(** Static import graph over the frozen Hermes reference.

    Extends the lexical static analysis ({!Hermes_analysis}, reused here for the
    file list) with an import edge list -- [import X] / [from X import Y], parsed
    lexically -- and an anchor-coverage summary: which {!Capability_catalog}
    source anchors are IMPORTED by something (referenced) versus never imported
    (orphaned).

    "Referenced vs orphaned" mirrors the zigvm orphan/reachability audit (R14).
    The Python-specific import extraction has no zigvm counterpart -- it is the
    Hermes domain, as Erl_tests is zigvm's -- but it follows the same lexical,
    honest-and-coarse discipline as {!Hermes_analysis}: no real parser, no
    execution, just a structural map of the surface the candidate must reproduce. *)

type edge = { source : string; target : string }  (** dotted module names *)

type summary = {
  module_count : int;
  edges : edge list;              (** deduped, sorted by (source, target) *)
  internal_edge_count : int;      (** edges whose target resolves within the tree *)
}

val module_of_path : string -> string
(** ["agent/transports/chat_completions.py"] -> ["agent.transports.chat_completions"];
    ["agent/__init__.py"] -> ["agent"]. *)

val imports_of_content : string -> string list
(** The import targets named on [import ...] / [from ... import ...] lines. *)

val analyze : root:string -> summary

type anchor_status = { anchor : string; module_name : string; referenced : bool }

val anchor_coverage : summary -> anchors:string list -> anchor_status list
(** For each anchor (a source path), whether its module is imported by some edge
    -- directly, or via its parent package. *)

val describe : summary -> string
