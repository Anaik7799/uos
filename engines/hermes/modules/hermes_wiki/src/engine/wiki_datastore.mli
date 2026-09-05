(* The DATASTORE — seven register rows that are one idea asked seven
   ways: a corpus is data, and everything you can do with data here goes
   through machinery that already exists.

     HW.5.1.1  from selector           monotone in the corpus
     HW.5.4.2  Bases                   same engine
     HW.5.4.3  Dataview / Datacore     total and law-tested, no JS
     HW.8.2.6  Version lifecycle       versions parse; total order
     HW.8.3.2  Database templates      same mechanism
     HW.8.3.3  Templater               computation in the HARNESS, not the template
     HW.8.3.7  Comments & discussions  notes with @comments-on; block-anchored

   THE ORGANISING REFUSAL: this module adds NO second engine. It has no
   query evaluator (every row it can show comes out of
   [Wiki_query.eval]), no template substitution (every page it can stamp
   comes out of HW.8.3.1's [Wiki_lifecycle.instantiate]), and no anchor
   table (every anchor it can resolve comes out of [Hermes_wiki.anchors]).
   Three surfaces, three borrowings, zero re-implementations. That is not
   tidiness: a second evaluator is a second answer, and the moment a Base
   and the engine disagree about which pages match `from type:claim` the
   Base is worse than not having been built.

   PURE: no filesystem, no Unix, no clock, no randomness, no network.
   Every fact arrives as an argument. The absence of a clock is load
   bearing twice over — there is deliberately no `now` template kernel
   (see HW.8.3.3), because a template that can read the day it ran is a
   template whose output is not reproducible, and HW.8.1.5 already
   settled that a fabricated date is a forged receipt.

   TOTAL at the edges, in the query engine's own sense: an unparseable
   base, an unparseable dataview, an unparseable version and an
   unresolvable comment each yield a NAMED value. Nothing here raises,
   and nothing here answers a bad input with an empty result — an empty
   result must always mean "nothing matched", never "we could not read
   what you wrote".

   DETERMINISTIC: every list this module emits is sorted before it is
   emitted. Nothing is keyed on a hash table's iteration order.

   CODE IS NOT PROSE. Markers parsed out of a body — dataview fences,
   `.. versionadded::` directives, `@comments-on:` lines — are read
   outside code fences only. A fenced `@comments-on:` DOCUMENTS the
   grammar; it does not use it. The corpus has twice produced reports
   that were entirely examples quoted in documentation, and both times
   the report was the bug.

   R14, and what is genuinely new. The query surfaces mirror zigvm's
   `docs_wiki.ml` zkquery (§2253-2485) by DEPENDING on its Hermes port
   rather than copying it, and [fences] is the tagged generalisation of
   [Wiki_query.fences] with the agreement pinned as a law (see below).
   The column-zero directive discipline is mirrored, with citation, from
   `Wiki_directive`. Templater, database templates and comments have no
   zigvm counterpart — zigvm's wiki has no template engine and no comment
   model — so they are stated fresh and the reason is recorded in
   `docs/hermes/zigvm-overlap-map.md`. *)

(* ============================================================== shared

   The tagged generalisation of [Wiki_query.fences], which is fixed to
   ```zkquery. Same walk, same closing rule, one parameter.

   THE MIRROR IS A LAW, NOT A COMMENT: [fences ~tag:"zkquery" body] must
   equal [Wiki_query.fences body] on every body, and the test asserts it.
   A generalisation whose agreement with the thing it generalises is only
   claimed in prose is a fork with better manners. *)
val fences : tag:string -> string -> string list

(* ================================================ HW.5.1.1 from selector

   The row's claim: "monotone in the corpus".

   Growing the corpus must not shrink a result. A reader who has a link
   to a query and comes back after ten new notes were written expects to
   find at least what they found before; a view that quietly loses rows
   as the corpus grows is a view nobody can cite.

   THE CLAIM IS NOT TRUE OF EVERY QUERY, AND SAYING SO IS THE POINT. Two
   families break it, and both are decidable from the query's syntax:

   - CORPUS-DEPENDENT FIELDS. `backlinks` and `degree` are properties of
     a page's NEIGHBOURHOOD, not of its bytes. Publishing one new note
     that links to `alpha` raises alpha's backlink count, so a query for
     `where backlinks<1` — the orphan report — LOSES alpha when the
     corpus grows. `slug`, `status`, `type`, `group`, `tag`, `words` and
     `outlinks` are page-local: rebuilding with more files leaves them
     alone.
   - `limit`. A bounded result is a PREFIX of a total order, and a new
     page can sort ahead of the last row and displace it. That is the
     bound behaving correctly, not a defect, which is exactly why the
     claim has to exclude it rather than pretend.

   The `from` selector itself — `all`, `type:T`, `group:G`, `tag:T` — is
   page-local in every form, which is why THIS row carries the claim.

   Two artefacts, and the pairing is deliberate: [monotone] is a
   SUFFICIENT SYNTACTIC condition decided from the query alone, and
   [monotone_defect] is the EMPIRICAL differential over two corpora. One
   without the other proves nothing — a classifier nobody checks against
   real corpora is an opinion, and a differential with no classifier
   cannot say which queries were supposed to pass. *)

(* The fields whose value for a page depends on OTHER pages. Exactly
   ["backlinks"; "degree"], sorted; both are [Wiki_query.int_fields]. *)
val corpus_dependent_fields : string list

(* Decided from the query alone, and TOTAL: [true] iff every condition
   names a page-local field and there is no `limit`. A [true] verdict is
   a promise that [monotone_defect] will find nothing, for any pair of
   corpora WHOSE SLUGS ARE DISTINCT — the qualifier is real, since the
   builder resolves a slug collision by renaming one side and a renamed
   page is not the page a `where slug=` result was holding. A [false]
   verdict is a refusal to promise, not an accusation. *)
val monotone : Wiki_query.query -> bool

(* The differential. Builds [base] and [base @ added] with
   [Hermes_wiki.build] — the real corpus builder, because the whole point
   is that adding FILES can change derived fields — evaluates the query
   over both, and reports the first slug present in the smaller result
   and absent from the larger. [None] means monotonicity held on this
   pair. The message NAMES the lost slug; "not monotone" on its own would
   send the reader back to the corpus with nothing to look for. *)
val monotone_defect :
  base:(string * string) list ->
  added:(string * string) list ->
  Wiki_query.query ->
  string option

(* Every `from` selector this corpus can answer, sorted and deduped:
   "all" plus `type:T`, `group:G`, `tag:T` for each value present. A menu,
   so a surface offering selectors offers only ones that resolve — a
   selector for a type no page has is the silently-empty result the
   totality law forbids, dressed as a feature. *)
val selectors : Hermes_wiki.page list -> string list

(* ======================================================= HW.5.4.2 Bases

   The row's claim: "same engine".

   A Base is a SAVED VIEW: a name, a zkquery, and the columns to show.
   It is a note like any other, so it diffs, reviews and travels with the
   corpus. What it is NOT is a query language — [base_rows] is defined as
   [Wiki_query.eval] applied to the query the base parsed, so the claim
   is true by construction rather than by testing, and the test then
   checks the construction survived.

   A base holds its PARSED query, not its source text. A base that
   carried only text would re-parse at every render and could be
   constructed in a state that never evaluates; parsing at construction
   makes an unparseable base unrepresentable, and its engine error is
   carried VERBATIM in [Base_query] so the author reads the engine's own
   words rather than a paraphrase.

   THE COLUMN VOCABULARY IS CLOSED, and two exclusions are deliberate.
   `tag` is not a column because a page has a SET of tags and a cell is
   one value; joining them would invent a string no query could match.
   `words` is not a column because computing it here would mean a second
   word counter, and a column that disagreed with the `where words>N` of
   the very same query is worse than a missing column. Both exclusions
   are checkable: [cell] answers [None] for anything outside
   [column_names]. *)

type base = {
  base_name : string;
  columns : string list;      (* in the author's order; not sorted *)
  source : string;            (* the zkquery text, verbatim *)
  query : Wiki_query.query;   (* parsed at construction: see above *)
}

type base_error =
  | Base_unknown_key of string     (* a `key:` the format does not define *)
  | Base_missing of string         (* a required key: "name" or "query" *)
  | Base_unknown_column of string  (* outside [column_names] *)
  | Base_query of string           (* the ENGINE's own named error, verbatim *)

val show_base_error : base_error -> string

(* The closed column vocabulary, sorted:
   backlinks, degree, group, outlinks, slug, status, title, type. *)
val column_names : string list

(* One cell. [None] for a name outside [column_names] — never "", which
   would be indistinguishable from a page whose status is unset.
   Integer columns render as decimal.

   THE CELL AGREES WITH THE ENGINE. For every column that is also a
   [Wiki_query] field, `where <column>=<cell>` returns a result
   containing that page; the test asserts it column by column. `title`
   is the one column with no `where` counterpart, and is marked as such
   here rather than left for a reader to discover. *)
val cell : Hermes_wiki.page -> string -> string option

(* The base format: `key: value` lines, order-free, blank lines ignored.
   Keys: `name` (required), `query` (required), `columns` (optional,
   comma-separated, default `slug, title`). An unknown key is a NAMED
   error and not a silent skip — a base whose `colums:` typo made its
   column list vanish would render a table the author did not write.
   Errors are collected and sorted: an author fixing a base wants the
   whole list. *)
val parse_base : string -> (base, base_error list) result

(* Definitionally [Wiki_query.eval pages b.query]. There is no other
   path. *)
val base_rows : Hermes_wiki.page list -> base -> Hermes_wiki.page list

(* Header row followed by one row per result, cells in column order. A
   column outside [column_names] cannot occur — [parse_base] refused it —
   so the table is total. *)
val base_table : Hermes_wiki.page list -> base -> string list list

(* ========================================= HW.5.4.3 Dataview / Datacore

   The row's claim: "total and law-tested, no JS".

   Dataview's surface is worth having; Dataview's evaluator is not.
   `dataviewjs` blocks run arbitrary JavaScript against the vault at
   render time, which makes a note a program and a reader a host. So this
   is a DESUGARING and nothing else: [to_zkquery] rewrites the surface
   into zkquery TEXT, [Wiki_query.parse] then judges that text, and
   [Wiki_query.eval] answers it. No expression is ever evaluated by this
   module, because this module contains no evaluator to reach.

   THE JS REJECTION IS STRUCTURAL, NOT A FILTER. A ```dataviewjs fence is
   collected by [dataview_js] and never handed to [to_zkquery], and
   [to_zkquery] has no branch that could run it if it were: its output
   type is a zkquery STRING. There is no code path from author text to
   execution to remove, which is a stronger statement than having removed
   one. The rejected fences are COUNTED and reported rather than dropped,
   because a silently ignored block looks to its author like a block that
   found nothing (R2: a skip is disclosed).

   KEYWORDS ARE UPPERCASE — TABLE, LIST, FROM, WHERE, AND, SORT, ASC,
   DESC, LIMIT — which is Dataview's own convention. Lowercase is a NAMED
   error, never a quiet alias: accepting `table` here and rejecting it
   there is how a grammar becomes folklore. *)

type dataview_error =
  | Dv_empty                    (* nothing to desugar *)
  | Dv_head of string           (* the first keyword is not TABLE or LIST *)
  | Dv_from of string           (* FROM takes #tag, "group", or all *)
  | Dv_where of string          (* a condition that is not FIELD OP VALUE *)
  | Dv_sort of string
  | Dv_limit of string
  | Dv_column of string         (* a TABLE column outside [column_names] *)
  | Dv_query of string          (* the ENGINE's named error, verbatim *)

val show_dataview_error : dataview_error -> string

(* The ```dataview fences of a body, in order. *)
val dataview_sources : string -> string list

(* The ```dataviewjs fences of a body, in order — REJECTED, never parsed,
   never evaluated, and returned so that the refusal can be counted and
   shown. *)
val dataview_js : string -> string list

(* One named diagnostic line per rejected JavaScript block, sorted. *)
val dataview_defects : string -> string list

(* Surface -> zkquery TEXT. The whole of this row's compilation, and its
   output is a string that [Wiki_query.parse] must still agree to. *)
val to_zkquery : string -> (string, dataview_error) result

(* [to_zkquery] then [Wiki_query.parse] then [Wiki_query.eval]. The test
   asserts equality against calling the engine directly on the desugared
   text, which is what "adds no evaluation path of its own" means when it
   is a measurement rather than a promise. *)
val dataview_rows :
  Hermes_wiki.page list -> string -> (Hermes_wiki.page list, dataview_error) result

(* A dataview block that names columns is a Base by another spelling, so
   it becomes one — one datastore concept, two surfaces. *)
val base_of_dataview : name:string -> string -> (base, dataview_error) result

(* ==================================== HW.8.2.6 version lifecycle directives

   The row's claim: "versions parse; total order".

   Sphinx's `.. versionadded:: 1.2`, `.. versionchanged::`,
   `.. deprecated::` and `.. versionremoved::`, at column zero, outside
   fences — the same discipline as `Wiki_directive`, mirrored here with
   citation because a lifecycle marker is a directive and should not be
   spelled a second way. (That library is not in this one's dependency
   set; the mirror is of the SHAPE, and the shape is: column zero, `.. `
   prefix, `::` separator, argument after it.)

   TOTAL ORDER, and the equality it is relative to. A version is a
   dot-separated run of decimal components, compared component-wise with
   the shorter side ZERO-EXTENDED, so `1.2` and `1.2.0` are the SAME
   version and not merely adjacent. Stating that is not pedantry:
   antisymmetry — [compare_version a b = 0] exactly when a and b denote
   the same release — is only true under that equality, and a total order
   whose equality is unstated is a sort key, not an order.

   Anything that is not that shape is a NAMED diagnostic and is NOT
   admitted as a release. `v1.2`, `1.2-rc1`, `1..2`, `1.` and `` are each
   refused with the text that was written, preserved verbatim: a
   normalised guess would erase the evidence the author needs to see.
   A version this module cannot order is a version this module will not
   pretend to have ordered. *)

type version = int list          (* the components, most significant first *)
type change = Added | Changed | Deprecated | Removed

val change_name : change -> string
val change_of_name : string -> change option

(* TOTAL. The error names what was rejected and quotes the input. *)
val version_of_string : string -> (version, string) result

(* Canonical text, trailing zero components removed: [1;2;0] shows as
   "1.2", so two versions that compare equal also SHOW equal. The empty
   version shows as "0". *)
val show_version : version -> string

(* Zero-extending component compare. A total order: reflexive,
   antisymmetric under the equality above, transitive, and trichotomous.
   The test checks all four over every pair of a fixture set rather than
   asserting them. *)
val compare_version : version -> version -> int

type release = {
  change : change;
  version : version;
  version_text : string;   (* as written, so a diff shows the author's form *)
  note : string;           (* the rest of the marker line, trimmed *)
}

(* Releases first by version, then by change (Added < Changed <
   Deprecated < Removed), then by note. Total, so a history is pinnable. *)
val compare_release : release -> release -> int

(* Every lifecycle directive in a body: the admitted releases SORTED by
   [compare_release], and the named diagnostics SORTED. Both, always —
   returning releases without diagnostics would let a malformed version
   vanish from a page that claims to show its history. *)
val releases : string -> release list * string list

(* The history as lines, one per release, deterministic. *)
val version_history : string -> string list

(* ============== HW.8.3.2 database templates / HW.8.3.3 Templater

   HW.8.3.2's claim: "same mechanism".
   HW.8.3.3's claim: "computation in the harness, not the template".

   A TEMPLATE IS NOT A PROGRAM, and this module is built so that it
   cannot become one. There is no [eval : string -> string] here, no
   expression type, and no place where author text is interpreted as
   anything but a NAME. Whatever computation a template can ask for comes
   from a CLOSED SET of kernels the harness implements — [kernel] is a
   variant with six constructors and no escape hatch — and a template
   selects one by writing its name. An unknown name is
   [Unknown_kernel]: a hard, named error that stops the whole
   instantiation. It does not fall through to a literal, it does not
   fall through to the empty string, and it does not fall through to
   "treat the slot as ordinary". That fall-through is the entire attack:
   a Templater feature that quietly ignores what it does not understand
   teaches authors to write things it does not understand.

   THERE IS NO SUBSTITUTION IN THIS MODULE. That is how "same mechanism"
   is proved rather than claimed. HW.8.3.1 already owns the one
   substitution in the system — [Wiki_lifecycle.template] and
   [Wiki_lifecycle.instantiate], fence-aware, with [Unfilled] and
   [Unknown_placeholder] collected — and this module produces the FILL
   LIST that goes into it. A database template and a page template
   therefore reach the page through the identical function, with the
   identical error names, because there is no second function for them to
   differ in.

   The row's cells are passed through VERBATIM, and that too is a
   decision. Projecting the row onto the template's slots first would
   make [Unknown_placeholder] unreachable from the database path — a
   column the template forgot would be silently discarded, and the author
   who filled it in would never learn that nothing read it. Passing the
   row whole lets HW.8.3.1 be the single judge of coverage in BOTH
   directions.

   A COMPUTED SLOT is written `{{kernel:column}}`; the column names a
   cell of the row. If that cell is absent the fill is OMITTED, and
   [instantiate] then reports [Unfilled "upper:title"] — the slot's own
   spelling, which names both the kernel and the missing column. Omission
   is the correct move only because the omission is loud downstream; it
   would be indefensible if [instantiate] tolerated a gap.

   THERE IS NO `now`, `date`, `random` OR `uuid` KERNEL. Every kernel is a
   pure function of its argument, so stamping the same template over the
   same row yields the same bytes forever. A clock kernel would make a
   template's output unreproducible and would manufacture exactly the
   authored timestamp R16 and HW.8.1.5 forbid. *)

type kernel =
  | Upper
  | Lower
  | Trim
  | Slug        (* [Hermes_wiki.slugify] itself, so a computed slug and a
                   corpus slug agree by construction rather than by luck *)
  | First_line
  | Length      (* in BYTES, decimal. Named honestly: this codebase does
                   not have a grapheme story and will not imply one *)

(* The closed set, by name, sorted. A surface listing what a template may
   compute lists exactly this. *)
val kernels : string list

val kernel_name : kernel -> string
val kernel_of_name : string -> kernel option

(* Total, pure, and total in the strong sense: every kernel is defined on
   every string, including "". *)
val apply_kernel : kernel -> string -> string

type slot =
  | Direct of string             (* {{title}} — filled from the row *)
  | Computed of kernel * string  (* {{upper:title}} — the harness computes *)

type template_error =
  | Unknown_kernel of string     (* THE security law. Never a fall-through *)
  | Empty_argument of string     (* `{{upper:}}` names no column *)
  | Off_schema of string         (* a row cell whose column the schema lacks *)
  | Unknown_row of string        (* a row key the database has not got *)

val show_template_error : template_error -> string

(* A placeholder NAME -> its slot. The split is at the FIRST colon, so
   `{{a:b:c}}` asks for kernel `a` and is refused by name. TOTAL. *)
val classify_slot : string -> (slot, template_error) result

(* The fills for a template's declared placeholders, given a row.

   Returns the row VERBATIM plus one entry per resolvable computed slot,
   deduped with the row winning, and SORTED by key. Sorting matters
   because [instantiate] reports its errors in fill-key order and a
   report whose order depends on how a row was assembled is not pinnable.

   [Error] iff some slot names something outside the closed kernel set —
   all such errors, deduped and sorted. On [Error] NO fills are produced
   at all: a partial fill set would let a caller stamp a page from a
   template it did not understand. *)
val fills :
  row:(string * string) list ->
  placeholders:string list ->
  ((string * string) list, template_error list) result

(* A DATABASE is a schema and keyed rows — a Notion database, or a Base
   over the corpus, which are the same object seen from two ends. *)
type database = {
  db_name : string;
  db_columns : string list;
  db_rows : (string * (string * string) list) list;  (* key, cells *)
}

(* The Base IS the database (HW.5.4.2 -> HW.8.3.2): rows keyed by slug,
   cells in column order, ordered by [base_rows] and therefore by the
   engine. Every row conforms to the schema by construction. *)
val database_of_base : Hermes_wiki.page list -> base -> database

(* The database path into [fills], and the ONLY thing it adds is schema
   conformance: an unknown row key and a cell whose column is off the
   schema are named before any kernel runs. Everything after that is
   [fills], and everything after THAT is HW.8.3.1's [instantiate]. *)
val database_fills :
  database ->
  row:string ->
  placeholders:string list ->
  ((string * string) list, template_error list) result

(* ========================================== HW.8.3.7 comments & discussions

   The row's claim: "notes with @comments-on; block-anchored".

   THE SERVER IS STATELESS AND THE CORPUS IS THE RECORD. A comment is not
   runtime state living beside the wiki; it is a note IN the wiki, whose
   body says what it discusses with a column-zero `@comments-on:` marker.
   Everything a comment gets for free follows from that: it diffs, it is
   reviewed, it is backed up with the corpus, it survives a restart
   because there was never anything to lose, and there is no second store
   whose disagreement with the corpus would have to be reconciled.

   The anchor is HW.3.3.1's. `@comments-on: alpha#^claim-1` resolves
   through [Hermes_wiki.anchors], which is the set of ids the RENDER
   emits — so an anchor a comment can reach is an anchor a reader can
   reach, and the two cannot drift because they are one list. A
   page-level comment omits the fragment and needs only that the page
   exists.

   AN ORPHAN IS A NAMED DIAGNOSTIC, in two flavours that are kept
   distinct because the fixes differ: [Missing_page] wants a target,
   [Missing_anchor] wants the anchor restored to a page that is otherwise
   fine. Collapsing them would send the reader to look for a deleted note
   that is sitting right there.

   ONE MARKER PER NOTE. A second marker is [Duplicate_marker] and the
   note contributes NO comment, because a comment whose subject is
   ambiguous is worse than a comment that failed to register: it would
   attach, arbitrarily, to one of two conversations. *)

type anchor = { target_slug : string; target_anchor : string option }
type comment = { comment_slug : string; on : anchor }

type comment_defect =
  | Empty_target of string                      (* commenting slug *)
  | Duplicate_marker of string                  (* commenting slug *)
  | Missing_page of string * string             (* commenting slug, target *)
  | Missing_anchor of string * string * string  (* commenting, target, anchor *)

val show_comment_defect : comment_defect -> string

(* The `@comments-on:` payloads of a body: COLUMN ZERO and outside code
   fences, in order. Indented or fenced markers are examples. *)
val comment_markers : string -> string list

(* `slug` or `slug#^id` or `slug#heading-anchor`. [None] when the target
   is empty, which is the one payload that names nothing at all. *)
val parse_comment_target : string -> anchor option

(* Every comment in the corpus and every defect, each sorted. Both,
   always: a discussion view that showed the resolvable comments and
   dropped the orphans would report a conversation that is missing
   replies and look complete. *)
val comments : Hermes_wiki.model -> comment list * comment_defect list

(* The comments on one slug, sorted — page-level and block-level
   together, since both discuss that page. *)
val thread : Hermes_wiki.model -> string -> comment list

(* The discussion surface: one deterministic line per comment, grouped by
   target slug in sorted order. *)
val discussion_report : Hermes_wiki.model -> string list
