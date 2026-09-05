(* THE REMAINING BLOCK-LEVEL DIALECT — six register rows that HW.2.0.1
   unblocked at once, because every one of them needs a block INSIDE a
   block and none of them needed anything else:

     HW.2.1.4   Nested lists                  depth(parse s) = depth(s)
     HW.2.1.11  Footnotes                     ref -> def -> ref is identity
     HW.2.3.2   Admonition titles + bodies    body is a Block list
     HW.2.3.3   Toggle list / details         summary inline, body blocks
     HW.2.3.5   Table of contents block       toc(a) subset anchors(render a)
     HW.2.0.3   Unused-directive lint         directive-like + unrecognised

   PURE. Text in, structured value out. No filesystem, no clock, no
   randomness, no global. The one thing this module reads from outside
   itself is [Hermes_wiki.render_markdown] with an empty resolver — a
   function of its argument, called so that HW.2.3.5's law can be
   COMPUTED against the production renderer rather than asserted about
   it (see [toc_resolves]).

   TOTAL. Nothing here raises, on any string. Malformed input is
   preserved VERBATIM and RECORDED as a diagnostic: an unclosed
   admonition, a footnote reference nobody defined, a directive nobody
   registered. [source_lines] is the proof, and it is the first law a
   reader should check —

     source_lines (parse s) = String.split_on_char '\n' s   for every s

   — because silently losing an author's text is the worst failure mode
   this codebase has, and a preservation law is the only thing that
   makes "total" mean more than "did not crash".

   CODE IS NOT PROSE, FROM THE START. A `:::note` inside a code fence, a
   `[^1]` inside inline backticks, a `[TOC]` inside a fence: each
   DESCRIBES the grammar and does not use it. Every scanner here tracks
   fenced regions on its line walk (mirror: Wiki_transclude.expand,
   Wiki_directive.parse_nodes), and the block grammars additionally
   require COLUMN ZERO, which excludes an inline-backticked copy by
   construction. This is not a nicety: the same confusion in the
   reference scanner reported 25 phantom embeds in a corpus with none,
   and 10 phantom dead links. INHERITED LIMIT, stated rather than
   fixed: backtick pairing is per-line, as it is everywhere else here,
   so an inline span crossing a line break leaks.

   REUSE, NOT REINVENTION (R14). The block carrier is [Wiki_ast.block] —
   nested lists are ordinary [List_block]s inside an [Item]'s body, so
   [Wiki_ast.render] renders them with no change and [Wiki_ast.depth]
   observes them. The admonition vocabulary and its emitter are
   [Wiki_callout]'s, so a `:::note` and a `> [!note]` cannot emit
   different markup. The heading anchors are [Hermes_wiki.slugify] under
   the same stateful collision rule the renderer uses. What is genuinely
   new here is only what did not exist: indentation-driven list nesting,
   the footnote pair, the colon-fence block, and the two lints. *)

(* ------------------------------------------------- HW.2.1.4 nested lists

   THE LAW IS DEPTH: depth(parse s) = depth(s). The left side is
   [list_depth], a structural fold over the parsed tree; the right side
   is [source_list_depth], a stack walk over the source's indentation
   that never builds a tree. Two independent computations of one number,
   so the law can fail — which is the only reason to state it.

   INDENTATION IS MEASURED IN COLUMNS, NOT CHARACTERS. A tab advances to
   the next multiple of four ([indent_columns]), so four spaces and one
   tab are the SAME level and mixing them does not invent a nesting
   level. A naive parser that counts characters reads `\t- b` as deeper
   than `    - b`; they are siblings.

   NESTING IS A STACK OF COLUMNS, NOT A DIVISION. The first list line of
   a run opens level 1 whatever its column, so a list that starts
   indented is depth 1 and not depth 3. A line at a smaller column POPS
   until the top is at most that column, so a dedent of three levels at
   once lands at the level it dedented to instead of one below the level
   it left.

   RUN BOUNDARIES: a BLANK LINE ENDS A LIST (which is what
   [Wiki_ast.parse] does), and so does a non-blank line at column zero
   that is not a list marker.

   TWO PLACES THIS DELIBERATELY DIFFERS FROM THE ORACLE, and both are
   consequences of the oracle having ONE flat list state where this has
   a stack. First, [Wiki_ast.parse] keeps a paragraph at column zero
   OPEN inside the list — the preserved `Loose` quirk that put a <p>
   inside a <ul> on every page published so far. Second, it computes an
   ordered list's `start` BEFORE closing a list of the other kind, so
   `- a` then `3. b` loses the 3; here the two lists are separate and
   the 3 survives. Neither quirk is representable in a nesting reading,
   so neither is reproduced, and the flat reading remains available and
   BYTE-IDENTICAL as [Wiki_ast.parse]. Nothing in the corpus render
   moves because of this module: no existing caller changes.

   MARKERS are the oracle's exactly — `- `, `* `, `N. `, `N) ` — because
   a marker this parser accepted and the renderer did not would be a
   list only one of them can see. An indented non-blank line that is not
   a marker CONTINUES the current item, joined with a single space (the
   oracle's paragraph rule). *)

(* The column of the first non-whitespace character, tabs advancing to
   the next multiple of four. [0] for a line with no indentation, and
   for a blank line. TOTAL. *)
val indent_columns : string -> int

(* The document as a block tree in which a list may contain a list.
   Everything that is not a list run is handed to [Wiki_ast.parse]
   unchanged, so this is the SAME dialect with one construct added, not
   a second parser. *)
val parse_lists : string -> Wiki_ast.t

(* The list-nesting depth of a parsed tree: 0 for a document with no
   list, 1 for a flat list, 2 for one nested level. Counts [List_block]s
   inside [List_block]s wherever they occur — inside an item, inside a
   quote, inside a callout. Distinct from [Wiki_ast.depth], which counts
   every block layer; on a document that is one list, [Wiki_ast.depth]
   is exactly one greater than [list_depth]. *)
val list_depth : Wiki_ast.t -> int

(* The same number read off the SOURCE: the maximum size the column
   stack reaches over any list run. Never builds a tree, so
   [list_depth (parse_lists s) = source_list_depth s] is a claim about
   two computations rather than a restatement of one. *)
val source_list_depth : string -> int

(* --------------------------------------------------- the block grammar

   HW.2.3.2 AND HW.2.3.3 ARE ONE GRAMMAR ASKED TWICE, so they are one
   parser here (the shape Wiki_directive uses for its six rows). The
   syntax is Docusaurus's colon fence at COLUMN ZERO:

     :::note Title            :::note[Title]        ::::warning
     body, as BLOCKS          body                  body
     :::                      :::                   ::::

   Three reasons, the same three that chose Obsidian's callout form in
   Wiki_callout. It DEGRADES — an unrendered block is visible prose, not
   a hole. It is the SOURCE dialect: these rows are imported from
   Docusaurus and Notion and an author who knows either writes this. And
   it is NOT a fence, which the fence-based rows already own; a grammar
   spelled as a fence could not say that a FENCED example is an example.

   THE CLOSER IS A COLON-ONLY LINE AT COLUMN ZERO WITH AT LEAST AS MANY
   COLONS AS THE OPENER. That single rule is what makes nesting work,
   and it is why the OUTER block takes more colons than the inner one:
   a `::::` closer ends a `::::` opener and passes straight through the
   `:::` inner block. Fenced regions inside the body are skipped while
   looking for the closer, so a ``` fence containing `:::` does not end
   the block. An opener with no closer clamps at end of input, keeps
   every line, and is RECORDED ([Unclosed_block]) — the same discipline
   as an unterminated fence in [Wiki_ast.parse].

   THE BODY IS A BLOCK LIST, which is HW.2.3.2's entire claim and the
   reason the row waited on HW.2.0.1. [body] is the recursive node list,
   so a block may hold another block; [body_blocks] is the same body as
   [Wiki_ast.t], so a body holding a nested list reports
   [list_depth >= 2] and a body holding a fence reports a [Fence]. A
   claim that a body is a block list is checkable exactly there.

   THE TITLE IS INLINE SOURCE, handed to the caller's inline renderer,
   never to an escaper: `:::tip **do** this` is emphasised in the title
   as it is in the body. An absent title falls back to the type name,
   which is [Wiki_callout]'s rule, unchanged.

   A TOGGLE IS THE FOLDABLE CASE OF THE SAME BLOCK (HW.2.3.3): the names
   `details` and `toggle` render through [Wiki_callout.html]'s
   `<details>`/`<summary>` path, so this module and a foldable callout
   cannot emit different disclosure markup. A toggle is CLOSED by
   default — an author writes a toggle to hide something, and a toggle
   that renders open is a toggle that did not happen; `+` opens it, `-`
   closes it explicitly. An admonition, by contrast, defaults to PLAIN
   and renders as a <div>: hiding a warning behind a click is the
   opposite of what a warning is for.

   LIMIT, STATED: Notion's toggle LIST — a list item that collapses its
   children — is not a second grammar here. It degrades to a nested list
   (HW.2.1.4), which is readable and correct; giving it a marker would
   need an inline-level dialect change this row does not own. *)

type kind =
  | Admonition of string
      (* the CANONICAL Wiki_callout type name, aliases resolved: an
         author's `:::tldr` is [Admonition "abstract"]. *)
  | Toggle of string
      (* `details` or `toggle`, as written — the word the author chose
         survives into the class name. *)
  | Unrecognised of string
      (* preserved verbatim, rendered, recorded. NEVER coerced to a
         known type: rewriting `:::warnign` to `note` turns a typo into
         a warning nobody sees. HW.2.0.3 is the report. *)

type fold =
  | Plain    (* no suffix: a <div>, not a disclosure *)
  | Open     (* `+`: <details open> *)
  | Closed   (* `-`, and a toggle's default: <details> *)

(* --------------------------------------------------- HW.2.1.11 footnotes

   A REFERENCE AND ITS DEFINITION ARE MUTUALLY REFERRING, and that is
   the whole feature. The marker carries `id=fnref-x` and links to
   `#fn-x`; the note carries `id=fn-x` and links back to `#fnref-x`. A
   footnote whose marker links to a note that does not link back is a
   dead end for a reader using a keyboard, so the pair is emitted from
   ONE source ([note_anchor] and [ref_anchor]) and the round trip is
   COMPUTED, not asserted: [footnote_links_resolve] checks that every
   footnote fragment the render emits has a matching id in that same
   render.

   DEFINITIONS ARE COLLECTED WHEREVER THEY WERE WRITTEN — at the top, in
   the middle, inside an admonition body, after the reference or before
   it. A definition is `[^id]: text` at COLUMN ZERO; its continuation is
   the indented lines that follow, blank lines included, up to the next
   non-blank line at column zero (mirror: Wiki_directive.scan_body).

   ORDERING IS BY FIRST REFERENCE, NEVER BY DEFINITION ORDER. The
   numbers a reader sees are the order they meet them in, so moving a
   definition to the bottom of the file must not renumber the page. A
   definition nobody references has no number at all.

   THE TWO FAILURES ARE DISTINCT DIAGNOSTICS BECAUSE THE FIXES DIFFER.
   [Undefined_footnote] means a marker points at nothing: the fix is to
   write the note. [Unreferenced_footnote] means a note nobody points
   at: the fix is to cite it or delete it. Collapsing them into "footnote
   problem" would tell an author which file to open and nothing else. A
   second definition of one id is [Duplicate_footnote]; the first
   definition wins and the second is preserved in [source_lines].

   AN UNDEFINED REFERENCE STILL RENDERS, LOUDLY. It keeps its number and
   its link, and the note it lands on says the definition is missing.
   Dropping the marker would make a missing note indistinguishable from
   a note that says nothing — the failure mode HW.9.2.1 and HW.3.5.1
   both refuse.

   THE ID ALPHABET IS [A-Za-z0-9_-], and that is a SINK decision, not a
   taste: the id reaches an HTML id and an href fragment unescaped, so
   anything outside the alphabet is not a footnote at all and is
   preserved as the text it is. Ids are case-sensitive, as the corpus
   writes them.

   NOT SCANNED, STATED: a marker in a block's TITLE is not a reference.
   Titles are inline source rendered by the caller, and a footnote whose
   number depended on a title's render order would be numbered
   differently by the two renderers. *)

type footnote = {
  fid : string;               (* the id as written *)
  label : int;                (* 1-based, BY FIRST REFERENCE *)
  definition : string list;   (* de-indented; [] when undefined *)
  defined : bool;
  refs : int;                 (* how many markers point here; always >= 1 *)
}

(* ------------------------------------------- HW.2.3.5 in-page contents

   THIS IS NOT Wiki_toc. HW.6.8.1's tree is the AUTHORED navigation of
   the CORPUS, declared in `toctree` fences and spanning documents. This
   is the DERIVED outline of ONE page, computed from that page's own
   headings and belonging to nobody else. Two things called a table of
   contents, sharing no code and no law; the pun is all they have in
   common.

   THE LAW IS AGREEMENT: every entry's anchor is an id the renderer
   actually emits. A ToC entry that does not resolve is worse than no
   ToC — no ToC costs a reader a scroll, a broken ToC costs them trust
   in every other link on the page. So the anchors are not slugified
   independently and hoped over: they come from the SAME stateful
   slugger the renderer uses (first occurrence keeps the plain slug,
   later collisions take -1, -2, …; an empty slug is `section`), applied
   to the SAME heading sequence, obtained by walking [Wiki_ast.parse] in
   the order [Wiki_ast.render] walks it — headings inside a quote, a
   callout or a list item included, because the renderer anchors those
   too. [toc_resolves] then CHECKS it against the production render, so
   the agreement is a computation and a drift in either slugger fails.

   THE MARKER IS `[TOC]` ON A LINE OF ITS OWN, outside a fence — the
   python-markdown / Notion form. It marks a PLACE, not a scope: the
   outline is the whole page's, so a `[TOC]` written before the headings
   still lists them all. A page with a marker and no headings is
   [Toc_without_headings]: an empty outline is a promise nobody kept. *)

type toc_entry = { level : int; text : string; anchor : string }

(* ----------------------------------------------------------- the nodes *)

type block = {
  name : string;              (* as written, trimmed *)
  kind : kind;
  colons : int;               (* the opener's colon count; the closer needs >= *)
  title : string;             (* INLINE SOURCE, "" when absent *)
  fold : fold;
  opener : string;            (* the opener line, verbatim *)
  closer : string option;     (* [None] iff unclosed *)
  body : node list;           (* RECURSIVE — the point of the row *)
  body_source : string list;  (* the body's lines, verbatim *)
}

and node =
  | Text of string list       (* verbatim prose; holds no block construct *)
  | Fenced of string list     (* opener .. closer, verbatim, INERT *)
  | Toc_marker of string      (* the `[TOC]` line, verbatim *)
  | Note_def of note_def      (* a footnote definition *)
  | Block of block

and note_def = {
  did : string;
  dtext : string list;        (* de-indented definition lines *)
  dsource : string list;      (* VERBATIM: marker line + continuation *)
}

(* The written word, whatever the kind — what a class name and a lint
   line both need, without either of them matching on the constructor. *)
val kind_name : kind -> string

(* ------------------------------------------------------- diagnostics *)

(* Typed rather than stringly, so a new failure mode cannot ship without
   every consumer's match failing to compile. Each is a NOTICE about the
   document; none raises, and none removes a byte from [source_lines]. *)
type diagnostic =
  | Unclosed_block of string
      (* a `:::name` that reached end of input. Clamped, kept, named. *)
  | Unrecognised_directive of string
      (* HW.2.0.3, first verdict: written in the block-directive form and
         in no vocabulary. The fix is to DEFINE it, or fix the spelling. *)
  | Unused_directive of string
      (* HW.2.0.3, second verdict: registered and used nowhere in this
         document. The fix is to USE it or drop the registration. A
         separate verdict because a separate fix; one "directive problem"
         would name neither. *)
  | Undefined_footnote of string
  | Unreferenced_footnote of string
  | Duplicate_footnote of string
  | Toc_without_headings

(* One printable line each. Deterministic. *)
val diagnostic_line : diagnostic -> string

(* ---------------------------------------------------------- the document *)

type t = {
  nodes : node list;
  notes : footnote list;      (* ordered by FIRST REFERENCE *)
  diagnostics : diagnostic list;
}

(* One pass, fence-aware, column-zero. TOTAL over every string. *)
val parse : string -> t

(* THE PRESERVATION LAW, and the first thing to check:

     source_lines (parse s) = String.split_on_char '\n' s

   for EVERY string s. An unclosed admonition, a footnote nobody
   defined, a directive nobody registered, a fence that never closes —
   all of it comes back byte for byte, in order. Unlike
   Wiki_directive.parse, this module moves NOTHING out of the document,
   so the identity has no exception at all. *)
val source_lines : t -> string list

(* Top-level blocks in source order, and every block including nested
   ones in source order. Both, because HW.2.3.2's nesting claim is about
   the second and HW.2.0.3's lint must see the second. *)
val blocks : t -> block list
val all_blocks : t -> block list

(* A block's body as [Wiki_ast.t] — HW.2.3.2's "body is a Block list",
   in the type that says so. *)
val body_blocks : block -> Wiki_ast.t

(* ------------------------------------------------------- observations *)

(* The page's headings, (level, text), in the order the renderer anchors
   them. Fence-aware by construction: a `# heading` inside a fence is
   [Fence] content in [Wiki_ast.parse] and never reaches here. *)
val headings : string -> (int * string) list

(* The in-page outline: one entry per heading, anchors from the
   renderer's stateful slugger. *)
val toc : string -> toc_entry list

(* Whether the page asks for one. *)
val has_toc_marker : string -> bool

(* The outline as markup. [escape] escapes the heading text, which is
   the honest conversion for a navigation label: a ToC entry is a
   destination, not a place to re-run emphasis. *)
val toc_html : escape:(string -> string) -> toc_entry list -> string

(* The ids the PRODUCTION renderer emits for a page —
   [Hermes_wiki.render_markdown] with an empty resolver, scanned for
   `id="…"`. Exposed so a disagreement can be inspected rather than
   merely reported. *)
val emitted_ids : string -> string list

(* HW.2.3.5's LAW, COMPUTED: every anchor in [toc s] is an id the
   production render of [s] emits. Vacuously true for a page with no
   headings, which is correct — the claim is that no entry dangles, not
   that entries exist. *)
val toc_resolves : string -> bool

(* The two halves of the footnote pair. ONE source for both directions,
   so the marker's target and the note's id cannot drift. The n-th
   reference to an id (1-based) gets its own anchor, so a note cited
   three times links back to each of the three. *)
val note_anchor : string -> string
val ref_anchor : string -> int -> string

(* HW.2.1.11's LAW, COMPUTED: every `#fn-…`/`#fnref-…` fragment the
   render of [s] emits has a matching id in that same render. This is
   `ref -> def -> ref is identity` as something that can fail. *)
val footnote_links_resolve : string -> bool

(* ------------------------------------------- HW.2.0.3 directive lint

   Two verdicts, because two fixes. [Unrecognised_directive] is a use
   with no definition; [Unused_directive] is a definition with no use.
   [registered] is the caller's vocabulary — supplied, never sensed, so
   a lint result is reproducible from its arguments alone (the
   discipline Wiki_directive.select uses for tags).

   SCOPE, DECLARED: "directive-like" here means THIS module's block
   grammar, `:::name`. Sphinx's `.. name::` markers are
   Wiki_directive's, and reporting them from here would mean carrying a
   second copy of that module's vocabulary that could drift from it. A
   corpus-wide lint composes the two; it does not duplicate either. *)

(* The CANONICAL names this module knows without being told: the
   thirteen Wiki_callout types, plus the toggle names. Aliases (`tldr`,
   `hint`, `error`, …) are recognised too, but through
   [Wiki_callout.kind_of_string] rather than from this list — the lint
   asks whether a name RESOLVES, never whether it appears here, so this
   list cannot go stale in a way that changes behaviour. It is exposed
   so a drift between the two vocabularies is visible to a test rather
   than only to a reader. *)
val builtin_directives : string list

(* [lint ~registered t]. [parse] already reports the unrecognised uses
   under an empty registry; this is the same computation with the
   caller's vocabulary added, plus the unused half, which no parse can
   know. *)
val lint : ?registered:string list -> t -> diagnostic list

(* -------------------------------------------------------------- render

   [inline] renders a raw inline run and [escape] escapes literal text —
   supplied by the caller, exactly as [Wiki_ast.render] takes them, so
   this module needs neither the link resolver nor the corpus and stays
   pure. Heading anchors come from a fresh slugger per call, mirroring
   the renderer, so two renders of one text are the same bytes.

   The footnote section is appended once, at the end, in first-reference
   order — a note is a page-level construct, not a paragraph-level one,
   and putting it anywhere else would make its number depend on where it
   was written. *)
(* HW.1.3.15 [hide_toc]: PRESENTATION ONLY. When set, the [TOC] marker
   renders as nothing — but the heading anchors, the footnote section and
   every other byte are unchanged, because the flag suppresses one nav
   element and touches no other decision. That is what makes it safe: a
   page whose author hid the contents list is still linkable at every
   heading, and a fragment link from another document into it still
   resolves. A flag that quietly changed the anchors would break inbound
   links the author never knew existed.

   Pinned as an EQUALITY, not as an absence: the two renders differ by
   exactly the nav and nothing else, and [emitted_ids] is identical. *)
val html :
  ?hide_toc:bool -> inline:(string -> string) -> escape:(string -> string) -> string -> string
