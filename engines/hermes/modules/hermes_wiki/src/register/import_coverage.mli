(* "ALL existing code reused and operationalized" — as a CHECKED claim,
   not an assertion. Every importable module in
   hermes_wiki/import/zigvm/code/ carries exactly one disposition here,
   and the suite fails when the import tree and this table disagree in
   EITHER direction: an unclassified module (something arrived and
   nobody decided) or a phantom row (a decision about a module that is
   not there). That biconditional is the whole point — the reconciliation
   discipline (S36) applied to reuse itself.

   The dispositions are honest about what "reused" means:

   - [Ported r]      its behaviour LIVES in the system now, under
                     register row(s) r — the strongest claim, and the
                     row's own probe is what proves it.
   - [Operational o] not ported as code, but its function is performed
                     by the named landed mechanism (usually because ours
                     supersedes it) — the module is retired, not ignored.
   - [Scheduled r]   a register row exists and names it as the mirror;
                     it is queued, and [next_mirrors] lists these.
   - [Superseded w]  the system deliberately does NOT do this, and [w]
                     is the invariant that holds BECAUSE it is absent
                     (the exclusion-invariant discipline).

   There is no "unknown" constructor: a module with no disposition
   cannot be represented, so the table cannot quietly go stale. *)

type disposition =
  | Ported of string list       (* register row ids *)
  | Operational of string       (* the landed mechanism that performs it *)
  | Scheduled of string         (* the register row that will port it *)
  | Superseded of string        (* the invariant that holds in its absence *)

type entry = { module_ : string; family : string; disposition : disposition }

val entries : entry list

(* Reconciliation against the import tree on disk. [declared] is what
   this table names; [observed] must be supplied by the caller (the test
   reads the directory — this module performs no IO). Both directions
   are returned, sorted. *)
val unclassified : observed:string list -> string list
val phantom : observed:string list -> string list

(* Reuse census, for the audit's log line: how many modules are Ported /
   Operational / Scheduled / Superseded. *)
type census = { ported : int; operational : int; scheduled : int; superseded : int }

val census : unit -> census

(* Every module still awaiting a port, with the row that will do it —
   the queue, derived from the table rather than remembered. *)
val next_mirrors : unit -> (string * string) list
