(* The PRESENTATION family, eight rows, one module — because they are one
   question asked eight ways: what does the reader actually receive, and
   is it still complete when the browser refuses to help?

     HW.7.1.2 Dark mode                  same names, rebound values
     HW.7.1.3 Print stylesheet           content-complete
     HW.7.2.2 Back-to-top                anchor + CSS, both surfaces
     HW.7.2.3 Skip-to-content            accessibility; anchor only
     HW.7.3.1 Syntax highlighting        server-side and TOTAL
     HW.7.3.2 Code language label        a pure function of the fence lang
     HW.7.3.4 Line highlighting          within range, or a diagnostic
     HW.7.8.1 Numbered figures/tables    derived from position

   THE HOUSE LAW OVER ALL EIGHT: NO SCRIPT. Every row here is an anchor
   plus CSS by construction — back-to-top and skip-to-content are
   `href="#id"`, dark mode is a media query over a rebound token set,
   syntax highlighting is spans emitted on the server. A feature that
   needs a runtime to work is not content-complete, because the first
   reader it fails is the one who turned scripting off, and the second is
   the printer. [has_script] is the mechanical form of that law and the
   suite applies it to everything this module emits.

   PURE, throughout. Values in, string out. No filesystem, no clock, no
   Unix — a presentation layer that reads the world cannot be byte-
   compared, and byte-comparison is how this corpus detects a hand edit
   (the HW.7.1.1 discipline, one layer up).

   AUTHOR TEXT IS ESCAPED AT EVERY SINK. An unescaped `<` inside a code
   fence is two faults at once: an injection, and a byte difference that
   makes the render baseline non-reproducible. [escape] is the single
   escaper; both surfaces use it, so equality holds by construction
   rather than by luck. *)

(* --------------------------------------------------------- the escaper *)

(* The four entities of the corpus escaper (mirror: `Hermes_wiki`'s own
   `escape_html`, which is not exported — this is the same four-way map,
   named here so both surfaces and the register probes share ONE). *)
val escape : string -> string

(* The inverse on the four entities. [unescape (escape s) = s] for every
   [s]: escaping is injective because each replacement starts with `&`,
   which is itself replaced first. Exposed because the round-trip law of
   the highlighter (below) is stated in terms of it. *)
val unescape : string -> string

(* Tags removed, then entities unescaped: the TEXT a reader sees. Total on
   any string, including malformed markup — an unclosed `<` swallows to
   end of input rather than raising. *)
val strip_markup : string -> string

(* True when the argument carries executable markup: a `<script`, a
   `javascript:` URL, or an `on…=` event attribute. The mechanical form of
   the no-script law. *)
val has_script : string -> bool

(* ------------------------------------------- HW.7.1.2 — dark mode *)

(* THE LAW, AND IT IS STRUCTURAL: the two modes bind the SAME TOKEN
   NAMES and only rebind their VALUES. Stated as a set equality —
   [token_keys Light = token_keys Dark] — because that is the property
   every component downstream depends on. A dark mode that introduces a
   token the light mode lacks leaves that variable undefined for exactly
   the readers who switched, which is the worst kind of bug: invisible to
   the author, total for the reader.

   THE DUAL, EQUALLY STRUCTURAL: every key is actually REBOUND. A token
   carrying the same value in both modes is not a theme token, it is a
   constant, and it belongs outside the palette where a reviewer can see
   that it never changes. So [palette Light] and [palette Dark] agree on
   every key and differ on every value.

   NO SCRIPT, TWO SELECTORS. Dark mode reaches the reader through
   `@media (prefers-color-scheme: dark)`, which needs no runtime, guarded
   by `:not([data-theme="light"])` so an explicit light choice still wins
   (R14 mirror: `wiki_theme_token_injector.safe_theme_tokens`). The
   `:root[data-theme="dark"]` block that `Wiki_theme` already emits is the
   explicit-override leg; neither leg requires the other. *)

type mode = Light | Dark

val modes : mode list
val mode_name : mode -> string

(* Token key -> value, sorted by key. The key is MODE-INDEPENDENT
   ("color/bg"); it is the name the law quantifies over. *)
val palette : mode -> (string * string) list

(* The keys alone, sorted. [token_keys Light = token_keys Dark] is the
   headline law of this row. *)
val token_keys : mode -> string list

(* "color/bg" -> "--color-bg". A CSS variable name is a key with its
   separators rewritten; nothing else. *)
val variable_of_key : string -> string

(* The palette projected into `Wiki_theme`'s vocabulary. Token paths are
   MODE-QUALIFIED ("dark/color/bg") because a token path is unique in
   `Wiki_theme` and two modes must be able to carry different values for
   one key. Every theme binds the same variable NAMES by construction, so
   `Wiki_theme.Mode_name_mismatch` cannot fire — the law is enforced by
   the shape of the data, not by a check that could be forgotten. *)
val theme_tokens : Wiki_theme.token list
val theme_themes : Wiki_theme.theme list

(* The `@media (prefers-color-scheme: dark)` block, built from the SAME
   sorted palette and carrying the SAME `/* token path */` annotations as
   `Wiki_theme.css`, so the two cannot drift. *)
val dark_media_css : string

(* `Wiki_theme.css` over [theme_tokens]/[theme_themes], with
   [dark_media_css] appended — composed with HW.7.1.1, never duplicating
   it. Error when the token layer refuses; the error is `Wiki_theme`'s,
   unwrapped, because inventing a second vocabulary for the same failure
   would make it harder to diagnose, not easier. *)
val theme_css : (string, Wiki_theme.error list) result

(* Every `--name` DECLARED (not merely referenced) in a stylesheet, sorted
   and deduplicated. The observation the set-equality law is checked
   with. Total on any string. *)
val declared_variables : string -> string list

(* ------------------------------------- HW.7.1.3 — print stylesheet *)

(* THE LAW IS CONTENT-COMPLETENESS: nothing that carries content may be
   hidden on paper. A printed page that silently drops a table is worse
   than one that prints badly, because the reader cannot tell that
   anything is missing.

   Proved as three set facts, not as a promise:
     1. everything `display:none` under `@media print` is in [print_chrome]
     2. [print_chrome] and [print_content] are DISJOINT
     3. nothing in [print_content] is hidden
   (2) is the leg that matters: without it, "hidden ⊆ chrome" is satisfied
   by simply declaring a content selector to be chrome.

   AND THE POSITIVE OBLIGATION: paper has no hyperlinks, so a link whose
   URL is not printed has lost its content. The print rules therefore
   DISCLOSE `attr(href)` after every link. A stylesheet that hides nothing
   but also discloses nothing is not content-complete either. *)

(* The declared chrome: navigation and controls, which have no meaning on
   paper. This list is the ONLY thing permitted to disappear. *)
val print_chrome : string list

(* Selectors that carry content. Membership here is a promise that the
   selector will render on paper, and [print_violations] checks it. *)
val print_content : string list

val print_css : string

(* Every selector hidden by a `display:none` rule inside the `@media
   print` block, split on commas and trimmed. Scoped to that block: the
   dark-mode media query nests braces too, and a parser that ignored
   scope would read its rules as print rules. Total; an unbalanced brace
   yields what it has read so far rather than raising. *)
val hidden_selectors : string -> string list

(* [] means the three set facts and the URL disclosure all hold. Each
   violation names the selector and why it is one. *)
val print_violations : unit -> string list

(* ----------------------- HW.7.2.2 / HW.7.2.3 — the two anchors *)

(* Both rows are the same mechanism and the same law: AN ANCHOR WHOSE
   TARGET EXISTS. Back-to-top is `href="#top"` and a `#top` landmark;
   skip-to-content is `href="#main"` and the content region's `id`.
   Neither needs a script, and neither may point at nothing —
   [dangling_anchors] is the mechanical check, and it runs over the
   ASSEMBLED page, so an anchor that only resolves in one surface is a
   failure in the other.

   ONE EMITTER, BOTH SURFACES. The static site and the Dream surface call
   [document_chrome]; byte-equality between them is by construction. The
   row says "both surfaces", and two copies of a fragment are two things
   to keep in step.

   SKIP-TO-CONTENT HAS A THIRD LAW, WHICH IS THE WHOLE POINT OF IT: the
   link is FIRST in source order. A skip link that comes after the
   navigation skips nothing. And it is off-screen, never `display:none` —
   a `display:none` element is removed from the focus order, so the
   commonest way to write this feature is also the way that breaks it.
   [skip_link_css] therefore positions it out of view and restores it on
   `:focus`. *)

val top_id : string     (* "top" *)
val main_id : string    (* "main" *)

val skip_link_html : string
val back_to_top_html : string
val top_landmark_html : string

(* The page chrome around a rendered body: skip link FIRST, the `#top`
   landmark, the `id="main"` content region, the back-to-top anchor last.
   [content] is already-rendered markup and is NOT escaped; every other
   byte is a constant of this module. *)
val document_chrome : content:string -> string

val skip_link_css : string
val back_to_top_css : string

(* Every `id="…"` defined, and every `href="#…"` referenced, in source
   order. Total on malformed markup. *)
val anchor_ids : string -> string list
val internal_hrefs : string -> string list

(* Referenced fragments with no matching id, sorted and deduplicated.
   [] is the law. *)
val dangling_anchors : string -> string list

(* ------------------ HW.7.3.1 / .2 / .4 — the code block *)

(* HW.7.3.1 — SERVER-SIDE AND TOTAL. Highlighting happens here, in a pure
   function, because a client-side highlighter is a script (the house
   law) and a byte-difference the baseline cannot pin.

   TOTAL means an unknown language DOES NOT CRASH AND DOES NOT GUESS: the
   body is emitted verbatim-escaped under the neutral class. That is the
   honest rendering — we do not know this language, so we claim nothing
   about it — and it is exactly what the row asks for.

   THE CLASS ATTRIBUTE IS DRAWN FROM A CLOSED SET ([code_classes]).
   `Wiki_ast.fence_html` charset-checks the language at the sink because
   author text reaches the class attribute there; this module removes the
   sink instead. Author text CANNOT reach the class attribute, because
   the class is a function of a three-constructor variant. The author's
   own token survives, escaped, in `data-lang`, where it is data.

   THE ROUND-TRIP LAW, which is the one that matters:
     [strip_markup (highlight_line l line) = line]
   for every language [l] and every line — the highlighter adds markup and
   changes nothing else. It kills a dropped token, a lost character, a
   mis-nested span and a missing escape in a single assertion.

   NO CROSS-LINE STATE, AND THIS IS DECLARED, NOT DISCOVERED. Each line is
   tokenized alone, so a construct that spans lines is not tracked: an
   unterminated string or comment at end of line is emitted as PLAIN
   text rather than colouring the remainder, because guessing would
   mis-colour every following line and a wrong colour reads as a claim.

   HW.7.3.2 — THE LABEL IS A PURE FUNCTION OF THE FENCE LANGUAGE, and of
   nothing else: not the body, not the position, not the surface.
   [label_of_lang] is that function. An absent language is an ABSENT
   label, not an empty one (the `sidebar_label` distinction, HW.1.3.13) —
   so `data-lang` is omitted entirely rather than emitted empty, and CSS
   `content: attr(data-lang)` draws it (R14 mirror: `docs_wiki.ml`'s
   `.cb[data-lang]::after`). Drawn by CSS, the label never lands in the
   copied text or the search index, which is why it is drawn that way.

   HW.7.3.4 — WITHIN RANGE, OR A DIAGNOSTIC. The row quantifies over
   LINES, so the rule is per request: a request inside `1 .. line_count`
   marks its line; a request outside NAMES ITSELF and marks nothing. It
   is never clamped. A clamped range moves the reader's attention to a
   line the author did not choose and reports success, which is the
   failure mode this row exists to prevent.

   Rendering never drops content: [code_block] always returns the block,
   and reports alongside it. A renderer that refused would delete the
   code because of a bad marker. [check_highlight] is the same rule as a
   pure predicate, for a caller that wants to refuse up front, and the
   suite pins that the two agree. *)

type language = Ocaml | Json | Shell

(* The closed alias table: "ml" and "ocaml" name one language. *)
val languages : (string * language) list

(* The fence language as `Wiki_ast.lang_of_info` produces it. [None] in,
   [None] out; an unrecognised token out is [None] too — that is the
   fallback, not an error. *)
val language_of_lang : string option -> language option

(* The closed set of class attribute values this module can emit. *)
val code_classes : string list
val code_class : language option -> string

(* The display label. [None] for an absent language: an absent label is
   not an empty label. *)
val label_of_lang : string option -> string option

(* One line to spans. Plain text when the language is [None]. The
   round-trip law above holds for every input. *)
val highlight_line : language option -> string -> string

type diagnostic =
  | Highlight_out_of_range of { requested : int; line_count : int }
  | Highlight_not_positive of { requested : int }

val describe : diagnostic -> string

(* R4's two coordinates. The level is L2 (a document's capability); the
   origin is Specification, because an out-of-range marker is something
   the AUTHOR declared — the renderer did exactly what it was told.
   Never Implementation, so by R5 this can never deny parity credit. *)
val diagnostic_level : diagnostic -> string
val diagnostic_origin : diagnostic -> string

(* The rule alone: every requested line not in `1 .. line_count`, in
   request order, deduplicated. [] iff every request is in range. *)
val check_highlight : line_count:int -> int list -> diagnostic list

type rendered = { html : string; diagnostics : diagnostic list }

(* The block. [lang] is the fence info's language (`Wiki_ast.lang_of_info`).
   LAW: [(code_block ?lang ~highlight body).diagnostics
         = check_highlight ~line_count:(List.length body) highlight] —
   the renderer and the checker are the same rule, so one cannot drift
   quietly from the other. *)
val code_block : ?lang:string -> ?highlight:int list -> string list -> rendered

val code_css : string

(* ------------------------- HW.7.8.1 — numbered figures and tables *)

(* DERIVED FROM POSITION, which is the entire content of the row. The
   number is the ordinal of the caption among captions OF ITS KIND, in
   source order, 1-based. Nothing is authored, so:

     - a duplicate number is UNREPRESENTABLE. Two figures with identical
       captions still get 1 and 2, because the caption is not the number;
     - inserting a figure RENUMBERS the ones after it, automatically, and
       every cross-reference follows because the reference is generated
       from the same value;
     - figures and tables count INDEPENDENTLY: [Figure; Table; Figure]
       numbers 1, 1, 2. One shared counter would make "Figure 2" the
       third object on the page, which is not what a reader counts.

   The anchor id is `figure-N` / `table-N`: two namespaces that cannot
   collide, and every [caption_ref_html] resolves against the
   [figure_html] of the same value — checked by [dangling_anchors], so
   this row is held by the same law as the two anchor rows. *)

type caption_kind = Figure | Table

val kind_name : caption_kind -> string

type numbered = {
  kind : caption_kind;
  number : int;        (* the ordinal among captions of this kind *)
  caption : string;    (* author text, VERBATIM here, escaped at emission *)
  id : string;         (* "figure-1" *)
}

(* Captions in source order to numbered captions in source order. Length
   and order are preserved: numbering observes position, it never
   reorders. *)
val number_captions : (caption_kind * string) list -> numbered list

(* "Figure 1". The label a reader reads and a reference cites; ONE
   function, so the two can never disagree. *)
val caption_label : caption_kind -> int -> string

(* [content] is rendered markup and is not escaped; [caption] is author
   text and is. *)
val figure_html : content:string -> numbered -> string

(* The cross-reference: an anchor to the figure, carrying its label. *)
val caption_ref_html : numbered -> string

val figure_css : string

(* ------------------------------------------------------ the whole sheet *)

(* Every rule this module owns, in one stylesheet: the theme (composed
   with HW.7.1.1), the two anchors, the code block, the figures, and the
   print rules last so they override. Error exactly when [theme_css]
   errors. *)
val stylesheet : (string, Wiki_theme.error list) result
