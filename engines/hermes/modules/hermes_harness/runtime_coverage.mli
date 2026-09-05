(** Runtime anchor coverage: which capability source anchors are EXECUTED when the
    frozen reference runs a scenario, versus which are not. The runtime
    counterpart to {!Hermes_imports}'s static reachability.

    Mirrors the zigvm coverage meter (R14): an honest covered / total / percentage
    report with no fabrication and no vacuous 100% — an anchor is covered iff its
    file appears in the executed set the tracing adapter recorded. The
    [sys.settrace] tracer that produces that set is the Hermes domain (Python),
    like the other reference adapters. *)

type anchor_status = { anchor : string; covered : bool }

type summary = {
  covered : int;
  total : int;
  statuses : anchor_status list;  (** sorted by anchor *)
}

val coverage : executed:string list -> anchors:string list -> summary
(** An anchor is covered iff it appears in [executed] (frozen-relative paths). *)

val percent : summary -> int
(** [covered * 100 / total], or 0 when [total = 0] — never a vacuous 100%. *)

val describe : summary -> string
