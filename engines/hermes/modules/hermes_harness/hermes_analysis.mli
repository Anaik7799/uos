(** Static analysis of the frozen Hermes reference.

    Read-only, lexical structural metrics over the reference's Python source, so
    the harness can reason about the surface it must reproduce WITHOUT running
    it. This is the static counterpart to {!Reference_capture}, which runs the
    reference for runtime analysis. Metrics are lexical (line/def/class counts),
    not a full parse -- an honest, coarse foundation the dashboard reports and
    capability research builds on. *)

type module_stat = { path : string; lines : int; defs : int; classes : int }

type summary = {
  files : int;
  lines : int;
  defs : int;
  classes : int;
  modules : module_stat list;  (** one per .py file, sorted by path *)
}

val analyze : root:string -> summary
(** Recursively scan [root] for [.py] files, skipping [__pycache__] and [.git],
    and total their lexical metrics. A [def]/[async def] at the start of a
    trimmed line is a definition; a [class ] is a class. A missing or unreadable
    root yields the empty summary rather than raising. *)

val describe : summary -> string
(** A one-line human summary: files, lines, defs, classes. *)
