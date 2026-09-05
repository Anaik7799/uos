(* Binding documentation to source — four rows that all say the same
   thing in different grammars: a document that talks about code must be
   DERIVABLE from that code, and where it cannot be derived it must say
   so rather than render something plausible.

     HW.9.1.3  API summary tables      — complete over the public interface
     HW.9.4.1  Documentation census    — the denominator is the whole point
     HW.9.2.2  literalinclude `:diff:` — a diff is derivable or it is decoration
     HW.9.2.3  Source cross-links      — a link resolves or it is not emitted

   PURE. Nothing here opens a file, reads a clock, or shells out. Every
   function that needs bytes takes an INJECTED reader (`~read`), exactly
   as `Wiki_include.slice` does, so every law below is a unit test rather
   than a filesystem fixture.

   ONE PARSE, NOT TWO. The interface surface comes from
   `Wiki_iface.items` (HW.9.1.2) and nothing here re-derives it. That
   module already carries the law that a doc comment attaches to the NEXT
   `val` only; a second parser here would eventually disagree with it,
   and the disagreement would surface as a coverage number that two
   modules compute differently.

   TOTAL at the edges. A missing file, an empty slice, an out-of-range
   line, an `.mli` with no vals, a val with no comment — every one is a
   defined value carrying a NAMED reason. Nothing raises; nothing clamps.

   R14 — the zigvm counterparts this mirrors are recorded in
   `docs/hermes/zigvm-overlap-map.md`: `slo_report.pct` (a zero
   denominator is never a rate), `ct_runner` (the oracle set stays the
   denominator; an attempt that produced nothing is UNTESTED, not
   absent), `stan_bridge` (censoring: absence of evidence is counted and
   DISCLOSED separately, never folded into a rate). *)

(* ------------------------------------------------------------ escaping *)

(* Text into HTML. Escapes `&<>` and BOTH quote forms, so one function is
   safe in element content and in an attribute value alike. An
   unescaped `<` arriving from a doc comment is an injection in a table
   cell, and doc comments are author text. *)
val escape_html : string -> string

(* ------------------------------------ HW.9.1.3 — API summary tables *)

(* One row per `val` the interface declares. [summary] is the first
   sentence of the attached comment, [""] when the val is undocumented —
   and an undocumented val is still A ROW. *)
type api_row = {
  name : string;
  signature : string;
  summary : string;
  documented : bool;
}

(* COMPLETE OVER THE PUBLIC INTERFACE: exactly one row per item of
   [Wiki_iface.items], in the same SOURCE order (the authored order is
   the documented order). Omitting the undocumented vals would make a
   summary table that flatters the module it documents — the reader would
   see a complete-looking API in which the gaps are invisible.

   TOTAL: any input, including one that declares nothing. *)
val api_rows : string -> api_row list

(* The rendered table. Every cell is escaped ([escape_html]).

   An undocumented row carries an EXPLICIT marker, never an empty cell: a
   blank summary reads as "nothing needed saying", which is the opposite
   of the fact.

   An interface that declares no values renders a NAMED NOTICE, never an
   empty `<table>`. An empty table is indistinguishable from a table the
   renderer failed to fill. *)
val api_table_html : string -> string

(* ---------------------------- HW.9.4.1 — documentation coverage census *)

(* What the census could do with a declared source. Three cases, and the
   distinction between the last two is load-bearing: [No_values] means we
   READ it and it declares nothing; [Unreadable] means we never saw it.
   Collapsing them would let an unreadable file hide in the bucket that
   sounds benign. *)
type status =
  | Measured                (* read, and it declares values *)
  | No_values of string     (* read, declares no recoverable value *)
  | Unreadable of string    (* the injected reader returned None *)

type entry = {
  path : string;
  status : status;
  documented : int;   (* 0 unless [Measured] *)
  total : int;        (* 0 unless [Measured] *)
  percent : float;    (* 0.0 unless [Measured] — see the law below *)
}

type census = {
  entries : entry list;    (* ONE PER DECLARED PATH, sorted by path *)
  declared : int;          (* = List.length entries, always *)
  measured : int;
  no_values : int;
  unreadable : int;
  items_documented : int;  (* over [Measured] entries only *)
  items_total : int;       (* over [Measured] entries only *)
}

(* The census over a DECLARED set of sources. The caller states what
   ought to be documented; duplicates collapse; the result carries one
   entry per declared path and DROPS NOTHING.

   THE HONEST DENOMINATOR IS THE WHOLE POINT. A coverage number computed
   over "the files we happened to read" is meaningless, because the
   cheapest way to raise it is to stop reading the bad ones. So:

     - an UNREADABLE source is DISCLOSED and stays in the denominator at
       0%, with its reason. It is never dropped.
     - a source that declares no recoverable value is 0%, not 100%:
       `Wiki_iface.coverage` already refuses 0/0, and the same refusal
       has to survive aggregation. This is also the reachable case
       without any IO failure at all — a file that is one unterminated
       comment READS fine and yields no items, and excluding it would
       inflate the number with nothing broken.

   The consequence is a STATED BOUND: an interface that legitimately
   declares only types drags the module mean down. That is deliberate.
   The alternative — excluding it — is a denominator that shrinks when
   content disappears, which is the failure this row exists to prevent. *)
val census : read:(string -> string option) -> string list -> census

(* The headline number: the mean of the per-module percentages over ALL
   declared modules, in [0,100]. [None] when nothing was declared — a
   census over nothing is not 0% and not 100%, it is no census
   (`slo_report.pct`'s refusal to make a rate from a zero denominator,
   strengthened from 0.0 to None because 0.0 is a number a dashboard will
   plot).

   Because the denominator is the DECLARED set, this number can only fall
   when a source becomes unreadable. A coverage percentage that rose
   because the denominator shrank is unrepresentable here. *)
val module_percent : census -> float option

(* The item-level ratio: documented vals over declared vals, in [0,100].

   [None] whenever [undetermined] is non-empty, and [None] when no items
   were counted. This is the CENSORING discipline (`stan_bridge`): a rate
   whose inputs are partly missing is not a smaller rate, it is not a
   rate. Read it with [disclosure] or not at all. *)
val item_percent : census -> float option

(* Why the item ratio cannot be reported: one named reason per unreadable
   source, sorted. Empty exactly when every declared source was read. *)
val undetermined : census -> string list

(* What was counted and what could not be read, as one line. This is the
   sentence the census is obliged to state alongside any number it
   reports; a percentage published without it is the number this row
   exists to distrust. *)
val summary_line : census -> string

(* One line per DECLARED path, sorted — including, and naming, the ones
   that could not be read. Length is always [declared]. *)
val disclosure : census -> string list

(* The census as a table, escaped. Carries [summary_line] and every
   entry, so a rendered census cannot show a number without its
   denominator. *)
val census_html : census -> string

(* ----------------------------- HW.9.2.2 — `literalinclude` with `:diff:` *)

(* An edit script over lines. [Keep] is context, [Del] leaves the before
   slice, [Add] enters the after slice. *)
type edit = Keep of string | Del of string | Add of string

(* The LCS table is quadratic, so it is BOUNDED. Past this many cells the
   diff degrades to "delete everything, add everything" — which is a
   worse-looking diff but a TRUE one: it still round-trips. A bound that
   degraded correctness instead of quality would be worse than no bound. *)
val max_lcs_cells : int

(* The minimal-ish edit script taking [before] to [after]. TOTAL,
   including over empty sides. *)
val diff_lines : before:string list -> after:string list -> edit list

(* THE ROUND TRIP, which is the whole law of this row:

     patch ~before (diff_lines ~before ~after) = Ok after

   for every pair of slices. A rendered diff must be DERIVABLE from the
   two slices it claims to compare; a diff that merely looks plausible is
   decoration. [patch] is also the check in the other direction — it
   REFUSES, with a named reason, an edit script whose [Keep]/[Del] lines
   do not match the before slice it was handed, so a diff cannot be
   silently applied to the wrong text. *)
val patch : before:string list -> edit list -> (string list, string) result

(* The `diff=PATH` selector in a fence info string. This is an OPTION ON
   `literalinclude`, not a parallel directive: the same path, the same
   `lines=`/`start-after=`/`end-before=`/`dedent` selectors are parsed by
   `Wiki_include.parse` and applied to BOTH sides, so the two slices are
   comparable by construction. [None] when no `diff=` token is present. *)
val diff_selector : string -> string option

type diff_render = {
  edits : edit list;
  before : string list;   (* the slice of the `diff=` path *)
  after : string list;    (* the slice of the directive's own path *)
  before_path : string;
  after_path : string;
}

(* [None] when the info string is not an attempted `literalinclude`
   carrying `diff=` — that is HW.9.2.1's directive, untouched.

   Otherwise a verdict, never silence:
     - `literalinclude diff=b.ml` names no source of its own — the base
       directive would take the SELECTOR as its path. That is an [Error]
       saying so, not a slice of a file named `diff=b.ml`.
     - an unreadable side, an unmatched marker, an out-of-range window:
       the [Error] `Wiki_include.slice` already names.
     - an EMPTY DIFF (the two slices are identical) is an [Error], not a
       success. Rendering an empty diff block asserts "here is the
       change" and then shows none, which is the stale-hand-copy failure
       `literalinclude` exists to abolish. *)
val diff_of_info :
  read:(string -> string option) -> string -> (diff_render, string) result option

(* The rendered diff, escaped. Every line carries its sign class so the
   markup, not colour alone, says what happened to it. *)
val diff_html : edit list -> string

(* --------------------------- HW.9.2.3 — source cross-links (viewcode) *)

type target = { file : string; line : int }

type xref = {
  name : string;
  target : target;
  href : string;    (* "file#Lline", attribute-escaped *)
  label : string;
}

type xrefs = {
  links : xref list;   (* in SOURCE order — the documented order *)
  gaps : string list;  (* named, sorted; one per link NOT emitted *)
}

(* The default reader: it resolves NOTHING. Present so a caller that has
   no source to inject still gets a defined value — and what it gets is
   total refusal with a reason on every path, never an empty render that
   looks like a module with no API. FAILS CLOSED, and says which. *)
val no_source : string -> string option

(* Lines in a source text. A trailing newline is a TERMINATOR, not an
   empty final line — the same reading `Wiki_include.slice` uses, so a
   range that is in-range for a slice is in-range here. *)
val line_count : string -> int

(* Does this target name a real location in the injected source? The file
   must be readable AND the line must lie in [1, line_count]. *)
val resolves : read:(string -> string option) -> target -> bool

(* One cross-link, or a NAMED REASON it cannot exist. A link into nothing
   is worse than no link: it tells a reader the source is over there and
   sends them nowhere. So an out-of-range line is a DIAGNOSTIC — never a
   line number clamped into range, which would produce a link that
   resolves to the wrong code and looks entirely healthy. *)
val xref_of : read:(string -> string option) -> name:string -> target -> (xref, string) result

(* Cross-links from an interface to its source.

   With [impl = None] each val links to its own `val` line in the
   interface. With [impl = Some path] each val links to the line
   DEFINING it in that implementation — located by a TOKEN-BOUNDED match
   on `let name` / `let rec name`, so `let apply` never resolves to
   `let apply_start`. A link that pointed at a neighbouring definition
   would satisfy [resolves] and still be wrong, which is why the
   boundary is part of the law and not an implementation detail.

   EVERY EMITTED LINK RESOLVES, by construction: [links] is built only
   from the [Ok] results of [xref_of]. A val whose definition cannot be
   found, or whose file cannot be read, contributes a GAP and no link. *)
val cross_links :
  read:(string -> string option) -> iface:string -> impl:string option -> xrefs

(* The rendered cross-link list, escaped, gaps included as visible
   diagnostics — a gap the reader cannot see is a gap that never gets
   fixed. *)
val xref_html : xrefs -> string
