(* HW.9.3.2–.6 — the doctest EXTENSION family. The parent builder
   (HW.9.3.1, `Hermes_wiki.doctest_drift`) proves one thing very well: a
   ```doctest fence whose `> input` lines render to the expected bytes.
   It cannot express a test that needs a fixture, a test that must be
   isolated from its neighbours, a test whose expectation is normalised,
   or a test that must not run in this environment. Those four gaps are
   this module, and each is a place where a documentation suite usually
   starts lying to itself.

   THE STANCE, stated once and enforced everywhere below: THE AUTHOR
   DECLARES, THE RUNNER OBEYS. Nothing here is inferred. Normalisation is
   inferred by no heuristic (HW.9.3.2), a skip is decided by no guess
   (HW.9.3.6), a group is joined by no proximity rule (HW.9.3.5). The
   failure mode this abolishes is the one that looks like success: a
   runner that decides two outputs are "close enough", or that quietly
   does not run a test, reports a green suite that proves nothing. That
   is the same trap as widening a volatile set until a comparison passes.

   PURE. The interpreter is INJECTED (`~eval`), exactly as
   `Wiki_include.slice` injects its reader, and the world it acts on is a
   caller-chosen value threaded through the run. No filesystem, no Unix,
   no exceptions used as control flow across this boundary: an example
   that fails is a VALUE (`Failed`), not a raise.

   TOTAL. Malformed input never raises. An option that does not parse, a
   pair that does not pair, a condition the environment cannot answer —
   each is a named `Refused`, never a silent pass and never a crash.

   THE FOUR OUTCOMES ARE FOUR, NOT TWO. `Passed`, `Failed`, `Skipped` and
   `Refused` are counted separately because they mean different things
   about the corpus. `Failed` says the example is wrong — an
   Implementation-origin fact. `Refused` says the runner could not obtain
   a verdict (unknown option, unpairable block, undeclared condition):
   it proves nothing about the example and must never be folded into
   either `passed` or `failed` (R5's shape, and R3: an absent result is
   never a passing one). `Skipped` is a test that did not run and SAYS SO
   (R2) — every skip and every refusal also appears in [disclosures], so
   a suite cannot go quiet.

   FENCE OWNERSHIP IS BY DECLARED MARKER, so the parent builder and this
   module can share the ```doctest tag without either checking what the
   other checks. A `>>>` run is a transcript case and belongs here
   (HW.9.3.3); a `> ` run is the parent's and yields no case here; a
   ```doctest fence declaring NEITHER is checked by nobody, which is the
   one outcome neither module may leave silent — see [unchecked], and the
   `Refused` case the runner raises for it. *)

(* ---------------------------------------------------------- grammar *)

type kind =
  | Testsetup    (* HW.9.3.4 — fixture, runs before its group's cases *)
  | Testcode     (* HW.9.3.2 — the code half of a declared pair *)
  | Testoutput   (* HW.9.3.2 — the expectation half of a declared pair *)
  | Testcleanup  (* HW.9.3.4 — fixture, runs AFTER, on every path *)
  | Transcript   (* HW.9.3.3 — ```doctest, `>>>` interpreter transcript *)

(* HW.9.3.2 — normalisation, DECLARED. Both flags default to false, so
   the default comparison is BYTE-EXACT. There is deliberately no
   "smart" mode: every relaxation of equality is an author's written
   act, because a runner that decides for itself when two outputs are
   close enough can no longer tell drift from noise. *)
type normalisation = {
  trim_whitespace : bool;      (* `:trim-whitespace:` — strip each line's
                                  ends, drop leading/trailing blank lines *)
  normalise_whitespace : bool; (* `:normalise-whitespace:` — collapse runs
                                  of spaces and tabs within a line to one *)
}

val no_normalisation : normalisation

(* The group a block joins when it declares none. Membership is by
   DECLARATION, never by document proximity: two adjacent fences are in
   different groups if they say so, and two fences pages apart are in the
   same group if they say so. *)
val default_group : string

(* The marker that makes a ```doctest fence a transcript case of THIS
   module rather than of `Hermes_wiki.doctest_drift`. *)
val transcript_marker : string

type header = {
  kind : kind;
  group : string;            (* `:group: NAME`, else [default_group] *)
  skipif : string option;    (* `:skipif: COND` — DECLARED, never inferred *)
  norm : normalisation;      (* declared flags only *)
  bad : string list;         (* option tokens that did not parse *)
}

(* [None] unless the fence's first info token names one of the five
   directives. TOTAL: an unknown `:option:` token, or an option whose
   argument is missing, never raises — it is RECORDED in [bad], and the
   runner REFUSES the block rather than running it under a header it
   only partly understood. Ignoring an unparsed option is how a
   `:skipif:` silently becomes "run it anyway".

   OPTION ARGUMENTS ARE WHITESPACE-FREE TOKENS. That is a real limit of
   this grammar, stated rather than hidden (the same limit
   `Wiki_include` states for its markers): a group name or a condition
   containing a space cannot be written. *)
val header_of_info : string -> header option

type block = {
  page : string;      (* the page slug, "" for a bare markdown string *)
  ordinal : int;      (* 0-based, document order among family fences *)
  head : header;
  body : string list; (* the fence body, verbatim *)
}

(* Every doctest-family fence of a markdown body, in document order. *)
val blocks_of_markdown : page:string -> string -> block list

(* The same over a whole corpus. MIRRORS `doctest_drift`'s exclusions,
   and must: an `allow_example_links` page is quoting the grammar rather
   than using it, and a `literalinclude` fence's body belongs to a file.
   Counting either as a test manufactures failures out of prose. *)
val blocks_of_model : Hermes_wiki.model -> block list

(* The groups present, sorted and deduplicated — the run order, so a
   report is deterministic under any input order. *)
val groups : block list -> string list

(* HW.9.3.3 — the transcript split, MIRRORING `doctest_groups` in the
   parent builder line for line: a run of marker lines is one input, the
   following unmarked lines (blank ends trimmed) are its expected
   output, and a new input after an output CLOSES the group. Order is
   preserved, because a partition is order-blind and an order-blind
   split turns a blank separator line into manufactured drift.

   `>>>` opens a statement, `...` continues one. A body carrying neither
   yields [[]] — it is not this module's to check. *)
val transcript_cases : string list -> (string list * string list) list

(* ```doctest fences that declare NEITHER marker: checked by this module
   and by the parent builder alike, i.e. by nothing. One sorted line
   each. A fence that looks tested and is not is worse than an untested
   one, so this can never be silent. *)
val unchecked : block list -> string list

(* ------------------------------------------------------- comparison *)

(* The ONLY equality this module uses. With [no_normalisation] it is
   `String.equal`. Every weakening is read off the DECLARED flags — the
   function has no other source of leniency, which is what makes
   "declared, not inferred" checkable rather than aspirational. *)
val compare_output : normalisation -> expected:string -> observed:string -> bool

(* ------------------------------------------------------------- run *)

(* What an injected interpreter reports. [Raised] is the interpreter
   saying the example itself blew up — a fact ABOUT the example, so it
   yields `Failed`. An OCaml exception escaping [eval] is a different
   thing entirely: it says the interpreter is broken, proves nothing
   about the example, and yields `Refused` with the world unchanged. *)
type eval_result =
  | Output of string
  | Raised of string

type status =
  | Passed
  | Failed of string   (* the example is wrong; the reason names both sides *)
  | Skipped of string  (* did not run, and says why (R2) *)
  | Refused of string  (* no verdict obtainable; never a pass, never a fail *)

type result = {
  id : string;        (* page#group#ordinal[.case] — stable under isolation *)
  grp : string;
  status : status;
  expected : string;
  observed : string;
}

type 'w group_run = {
  name : string;
  results : result list;
  world : 'w;         (* the world AFTER cleanup — cleanup's effect is visible *)
}

type 'w report = {
  runs : 'w group_run list;
  passed : int;
  failed : int;
  skipped : int;
  refused : int;
  disclosures : string list;  (* one line per skip and per refusal *)
}

(* [run_group ~eval ~world ~env ~group bs] runs exactly the blocks of
   [group], starting from [world].

   ORDER WITHIN A GROUP: every `testsetup`, then the cases in document
   order, then every `testcleanup`. The world threads through all three
   phases, which is what makes a group a shared namespace.

   HW.9.3.4 — CLEANUP RUNS ON EVERY PATH. Not only when the cases pass:
   also when one fails, when the setup itself failed, when every case
   was skipped, and when there are no cases at all. A fixture that only
   tears down after success leaves the world dirty exactly when it
   matters, and the next group inherits a mess it did not make. Cleanup
   is therefore not guarded by any outcome, and [world] in the result is
   post-cleanup so the effect is observable rather than asserted.

   A SUCCESSFUL FIXTURE IS NOT A TEST and produces no result — it would
   otherwise inflate [passed] with work nobody claimed. A fixture that
   fails, refuses or is skipped DOES produce one, named for its phase.

   FAIL-CLOSED ON A MISSING FIXTURE (R19): if a `testsetup` fails, or is
   skipped by its own `:skipif:`, the group's cases are `Refused` — not
   run without their fixture, and not silently passed. A case run
   without the state it declared it needs produces a plausible answer,
   which is the worst kind. Cleanup still runs.

   HW.9.3.6 — [env] answers a DECLARED condition: [Some true] skip,
   [Some false] run, [None] the environment cannot say. [None] is
   `Refused`, never "run it anyway" and never "skip it quietly": an
   unanswerable condition is an unknown, and an unknown that reads as
   healthy is the defect R19 exists to prevent. *)
val run_group :
  eval:('w -> string -> 'w * eval_result) ->
  world:'w ->
  env:(string -> bool option) ->
  group:string ->
  block list ->
  'w group_run

(* HW.9.3.5 — THE ISOLATION LAW, and the reason this module exists at
   all: RUNNING THE GROUPS TOGETHER IS RUNNING EACH ONE ALONE.

   Precisely: for every group [g] of [bs],
     (run ~eval ~world ~env bs).runs, restricted to [g]
   is EQUAL — same results, same ids, same statuses, same final world —
   to
     (run ~eval ~world ~env (blocks of bs whose group is g)).runs.

   It holds by construction: [run] is a MAP of [run_group] over
   [groups bs], each call handed the same initial [world]. Nothing
   threads from one group into the next, so no group can be made to pass
   by a neighbour's leftovers, and no group can be broken by one.
   Ordering, too: the runs come out in [groups] order regardless of the
   order the blocks arrived in.

   Why this is load-bearing: a doctest suite is read as evidence that
   each example works. If group B only passes because group A ran first,
   the suite proves something about the corpus's ORDER, not about the
   examples — and it will keep passing after the example it documents
   has stopped working alone. *)
val run :
  eval:('w -> string -> 'w * eval_result) ->
  world:'w ->
  env:(string -> bool option) ->
  block list ->
  'w report
