(* The Sphinx DIRECTIVE FAMILY — six register rows that are one grammar
   asked six ways. HW.2.6.1 seealso, HW.2.6.2 rubric, HW.2.6.4
   productionlist, HW.2.6.5 only, HW.2.6.8 authorship, HW.2.7.1 field
   lists / docinfo.

   THE SYNTAX IS RST'S OWN, AT COLUMN ZERO: `.. name:: argument`, with an
   INDENTED body. Three reasons, the same three that chose Obsidian's
   callout form in Wiki_callout. It DEGRADES: an unrendered directive is
   a visible paragraph, not a hole. It is the SOURCE dialect — these six
   rows are imported from Sphinx and an author who knows Sphinx writes
   this. And it is NOT a fence, which the fence-based rows (toctree,
   doctest, code options) already own; a directive grammar spelled as a
   fence could not state the law below, because it would have no way to
   say that a fenced directive is an example.

   CODE IS NOT PROSE. A `.. seealso::` inside a code fence, and a
   `` `.. rubric:: X` `` inside inline backticks, DESCRIBE the grammar;
   they do not use it. Both are preserved verbatim and produce no
   directive, no edge and no diagnostic. This is not a hypothetical
   nicety: the same confusion in the reference scanner reported 25
   phantom embeds in a corpus with none, and 10 phantom dead links.
   Fenced regions are tracked on the line walk (mirror:
   Wiki_transclude.expand); inline backticks are excluded by the
   column-zero rule, since a marker preceded by a backtick is not at
   column zero. INHERITED LIMIT, stated rather than fixed: like
   Hermes_wiki's own scanner, backtick pairing is per-line, so an inline
   span that crosses a line break leaks.

   NOTHING THE AUTHOR WROTE IS EVER LOST. Every line of the input lands
   in exactly one node, verbatim, including the lines of a directive
   this module does not know. [source_lines] reconstructs the input
   exactly, and that is the law a reader should check first: an UNKNOWN
   directive is preserved and RECORDED, never dropped. Silently losing
   an author's text is the worst failure mode this codebase has. *)

(* ------------------------------------------------------------- the six *)

type kind =
  | Seealso              (* HW.2.6.1 — its entries are GRAPH EDGES *)
  | Rubric               (* HW.2.6.2 — a heading that is not a heading *)
  | Productionlist       (* HW.2.6.4 — a grammar; refs(g) subset defs(g) *)
  | Only                 (* HW.2.6.5 — conditional on a DECLARED tag set *)
  | Authorship of string (* HW.2.6.8 — sectionauthor|moduleauthor|codeauthor *)
  | Unknown of string    (* preserved verbatim, recorded, never coerced *)

(* The canonical kind for a written name, lowercased. An unrecognised
   name becomes [Unknown] carrying the author's spelling — the same
   discipline as Wiki_callout.kind_of_string and the discourse
   vocabulary, and for the same reason: rewriting `.. seelaso::` to
   something known turns a typo into a silent behaviour change. *)
val kind_of_name : string -> kind

(* The canonical lowercase name. [Authorship] and [Unknown] keep what was
   written, so a page shows the author's own word. *)
val kind_name : kind -> string

type directive = {
  kind : kind;
  name : string;                  (* as written, trimmed *)
  argument : string;              (* text after `::` on the marker line *)
  fields : (string * string) list;
      (* HW.2.7.1 BLOCK-SCOPED field list: a `:name: value` run at the
         head of THIS body is THIS directive's options. It is not
         document metadata, and it never reaches [docinfo]. That
         scoping is the row's claim, so it is structural here rather
         than a convention. *)
  body : string list;             (* de-indented, blank edges trimmed *)
  source : string list;           (* VERBATIM input lines: marker + body *)
}

type node =
  | Text of string list           (* verbatim prose, contains no directive *)
  | Heading of { level : int; text : string; source : string }
      (* an ATX heading, `#`..`######` at column zero. The ONLY thing
         that enters [toc] and [anchors] — which is exactly what makes
         HW.2.6.2's negative law checkable. Setext headings are out of
         scope here; the corpus writes ATX. *)
  | Fenced of string list         (* opener .. closer, verbatim, inert *)
  | Block of directive

(* ------------------------------------------------------- diagnostics *)

(* Typed rather than stringly, so a new failure mode cannot be added
   without every consumer's match failing to compile. Each is a NOTICE
   about the corpus; none of them ever raises, and none of them removes
   an author's bytes from [source_lines]. *)
type diagnostic =
  | Unknown_directive of string
      (* a `.. name::` this module does not know. Preserved verbatim. *)
  | Missing_argument of string
      (* a directive whose argument carries its meaning (rubric, only,
         productionlist, an authorship role) was written bare. *)
  | Decorative_seealso of string
      (* HW.2.6.1's dual: a see-also whose body yields NO edge. It
         renders and links nowhere, which is decoration, not a
         cross-reference. Carries the body's first line, so the author
         can find it. *)
  | Undefined_production of string * string
      (* HW.2.6.4: (grammar, referenced name) with no definition in that
         grammar. Unqualified refs only — a qualified `other:name` ref
         addresses a grammar this document may not contain, and is
         deliberately OUT OF SCOPE rather than half-checked. *)
  | Malformed_production of string
      (* a productionlist body line that is neither `name: def` nor a
         continuation of one. *)
  | Undeclared_tag of string
      (* HW.2.6.5: an `only` expression named a tag in neither the
         declared nor the active set. It evaluates FALSE — fail closed,
         a tag nobody declared cannot switch content on — and the block
         it guards is EXCLUDED and COUNTED, never silently dropped. *)
  | Malformed_condition of string
      (* an `only` expression that does not parse, or is empty. Same
         clamp: excluded, counted, never raised. *)
  | Docinfo_conflict of string
      (* HW.2.7.1: a docinfo field naming a key the frontmatter already
         declares. Two answers to one question is a defect in the
         document, and the module refuses to pick a winner behind the
         author's back. *)

(* One printable line per diagnostic. Deterministic. *)
val diagnostic_line : diagnostic -> string

(* --------------------------------------------------------- the document *)

type t = {
  frontmatter : string list;      (* declared keys, lowercased, for conflicts *)
  preamble : string list;         (* a leading `---` block, verbatim *)
  docinfo : (string * string) list;
      (* HW.2.7.1 DOCINFO: the field list at the very top of the body.
         It is METADATA, so it appears HERE and in NO [Text] node — a
         field that both answers a query and renders as prose is
         rendered twice and means two things. Names lowercased; values
         verbatim. A field list anywhere else is body text or a
         directive's options: docinfo is a document-leading construct,
         which is what "block-scoped" means. *)
  docinfo_source : string list;   (* those lines, verbatim, so nothing is lost *)
  nodes : node list;
  excluded : (string * string list) list;
      (* HW.2.6.5: every block [select] withheld, as (expression, its
         verbatim lines). Empty until [select] runs. Content that leaves
         a document without a receipt is INVISIBLE LOSS — the one
         outcome a conditional must never produce. *)
  diagnostics : diagnostic list;
}

(* [parse ~frontmatter text] over a document BODY. [frontmatter] is the
   set of keys the page's frontmatter declares, supplied by the caller
   (Hermes_wiki already parses frontmatter; this module does not compete
   with it) — it is used only to detect HW.2.7.1 conflicts. When [text]
   itself opens with a `---` block, its lines are kept verbatim in
   [preamble] and its keys are unioned into [frontmatter], so calling
   this on a raw page is safe rather than merely tolerated.

   TOTAL. Malformed input clamps to a defined value or is preserved
   verbatim with a diagnostic; nothing here raises, on any string.

   Conditionals are NOT evaluated: [parse] leaves each `only` as a
   [Block], because its content is undecided until a tag set is named.
   Observations therefore do not look inside a conditional — call
   [select] first. *)
val parse : ?frontmatter:string list -> string -> t

(* THE PRESERVATION LAW, and the first thing to check:

     source_lines (parse s) = String.split_on_char '\n' s

   for EVERY string s. An unknown directive, a malformed field, a
   half-written condition, a fence that never closes — all of it comes
   back byte for byte. [docinfo] is the one construct this module MOVES
   (out of the body, into metadata) and [docinfo_source] is why moving
   it is not losing it.

   After [select] the identity no longer holds, and must not: a
   conditional build is a different document. What holds there is the
   conservation law — every withheld line appears in [excluded]. *)
val source_lines : t -> string list

(* Top-level directives in source order. *)
val directives : t -> directive list

(* ------------------------------- HW.2.6.5 — conditional content (only) *)

(* [select ~declared ~active t] resolves every `only` against a DECLARED
   tag set. The tags come from the CALLER; nothing here reads the
   environment, the filesystem or a global. A build is reproducible
   because its condition is an argument.

   - [declared] is the vocabulary of tags this build knows; [active] is
     the subset that is true. [active] is implicitly declared (the union
     is the vocabulary), so a caller need not name a tag twice.
   - A tag in an expression and in NEITHER set is [Undeclared_tag]: it
     evaluates false and its block is excluded and counted. Fail closed
     — content switched on by a tag nobody declared is content nobody
     can reproduce.
   - The expression grammar is Sphinx's: tags, `and`, `or`, `not`,
     parentheses. Anything else is [Malformed_condition], with the same
     clamp.
   - `only` NESTS: a kept block's body is parsed and selected in turn.
   - A kept block's body is SPLICED into the node list, so a heading
     inside a kept conditional is a heading of this build.

   THE ROW'S CLAIM IS "anchors computed per build", and this is where it
   becomes true: two [select]s of the SAME [parse] with different active
   tags yield different [anchors]. An anchor set fixed at parse time
   would be a lie in every build but one. *)
val select : declared:string list -> active:string list -> t -> t

(* Total lines withheld by [select]. The countability the row needs in
   one number: zero means nothing was dropped, and any other number can
   be traced through [excluded]. *)
val excluded_lines : t -> int

(* ---------------------------------- HW.2.6.1 — seealso entries are edges *)

(* The see-also entries as GRAPH EDGES (source, target). A see-also that
   renders but does not link is decoration — so these are extracted as
   pairs, not merely rendered, and the extraction is exactly the one
   Hermes_wiki uses for [page.outlinks] (fence- and inline-code-aware
   payloads, then `slugify o strip_fragment`). MIRROR, not a second
   implementation: the edges of a seealso are therefore a SUBSET of the
   page's outlinks by construction, and cannot drift from them.

   The ARGUMENT is an entry too: `.. seealso:: [[alpha]]` is the one-line
   form, and reading only the indented body would make it render, link
   nowhere, and then be reported as decoration — a diagnostic about the
   reader rather than about the document.

   ONLY a seealso contributes. A rubric title, an authorship name and an
   unknown directive's body may each be spelled like a wikilink, and none
   of them becomes an edge; [authorship] says why that one matters.

   Source order, first occurrence kept. A seealso inside an unselected
   conditional contributes nothing — see [select]. *)
val edges : source:string -> t -> (string * string) list

(* --------------------------------------- HW.2.6.2 — rubric, negatively *)

(* The rubric titles, in source order. A rubric is a heading-LOOKING
   thing and must be a heading-looking thing only: it takes a title, it
   marks a section of prose, and it enters NEITHER [toc] NOR [anchors].
   The law is negative, so the way to check it is negative: build a
   document whose rubric title is IDENTICAL to a real heading's, and
   observe that [anchors] holds one entry, not two.

   Why it must be so: a table of contents is a NAVIGATION contract — a
   reader clicks an entry and arrives somewhere. A rubric has no
   somewhere; it is a label. An anchor for it would be a link target no
   document ever links to, and a toc entry for it would be a promise of
   a destination that does not exist. *)
val rubrics : t -> string list

(* The heading structure of THIS build: (level, text, anchor). Headings
   ONLY — never a rubric, never an authorship line, never a directive
   argument. Anchors are [Hermes_wiki.slugify] of the heading text. *)
val toc : t -> (int * string * string) list

(* The anchor set of THIS build: the anchors of [toc], in order. *)
val anchors : t -> string list

(* ----------------------------------- HW.2.6.4 — productionlist grammars *)

type production = {
  grammar : string;       (* the directive's argument; "" when written bare *)
  pname : string;
  definition : string;
  refs : string list;     (* the `backticked` names it references *)
}

(* Every production of the document, source order. Blocks SHARING an
   argument are ONE grammar — Sphinx's continuation semantics — so a
   grammar may be written in as many pieces as the prose wants without
   its references becoming undefined. *)
val productions : t -> production list

(* THE ROW'S LAW, refs(g) subset defs(g), as the misses: (grammar, name)
   for every unqualified reference with no definition in its own
   grammar. Sorted, deduped. Empty is the healthy state.

   Resolution is PER GRAMMAR, not corpus-wide: two grammars may both
   define `expr` and mean different things, so a reference that resolves
   across grammars would silently pick one. *)
val undefined_productions : t -> (string * string) list

(* ------------------------------------ HW.2.6.8 — authorship directives *)

(* (role, name) for each authorship directive, source order — where role
   is `sectionauthor`, `moduleauthor` or `codeauthor` as written.

   PRESENTATIONAL ONLY, and that is the whole law. This list is what a
   renderer may PRINT. It is not metadata: an authorship directive never
   reaches [docinfo], never creates an [anchors] entry, never creates a
   [toc] entry, and never creates an edge — not even when its argument
   is spelled like a wikilink. A byline that quietly became a graph edge
   would make the authorship of a page indistinguishable from its
   subject matter. *)
val authorship : t -> (string * string) list
