(* HW.6.2.1, HW.6.3.7, HW.6.5.1, HW.6.9.2, HW.6.9.3, HW.6.10.1 — the
   EXPORT surfaces: the six ways this corpus leaves the corpus.

   They belong in one module because they are one question asked six
   ways: given the built model, what does a consumer that is NOT this
   renderer get, and can it be shown to have got the same thing? Every
   law below is a form of that question, and the module exists to make
   each of them mechanically checkable rather than plausible.

   PURE, and TOTAL. No filesystem, no clock, no randomness, no Unix; a
   reader is injected where one is needed (HW.6.3.7's search). Every
   function is defined on the empty corpus, on a page with no words, and
   on a title made entirely of markup — none of them raises.

   DETERMINISTIC BY LAW. Every list this module emits is sorted before
   it is emitted; nothing is folded out of a hash table into output. Two
   runs over an unchanged corpus produce BYTE-IDENTICAL exports, so a
   diff of an export is a change in the corpus and never noise. Nothing
   carries a timestamp, a host name or a version of anything that moves:
   a generated-at line would break that law on its own.

   ESCAPING IS PER-GRAMMAR. Each surface escapes its own text for its
   own target — [json_string] for JSON, [html_escape] for HTML — because
   an unescaped quote does not corrupt a document, it corrupts the
   PARSE of a document, and a consumer then reads a different corpus
   than the one that was exported. The tests feed the emitters bytes the
   live corpus does not happen to contain: an escaping fault that only
   fires on an authored quote is invisible until someone writes one.

   R14 — this module MIRRORS rather than reinvents: [json_string] takes
   its shape from `Feature_model.escape_quoted` (widened to the control
   range), the canonical-then-digest discipline from
   `Wiki_build.serialise`, the collision-breaking counter from
   `Hermes_wiki`'s slug disambiguator, and HW.6.3.7 exports the index
   `Wiki_search` already built rather than building a second one. The
   correspondences are recorded in `docs/hermes/zigvm-overlap-map.md`. *)

(* ------------------------------------------------------------ shared *)

(* HTML text escaping: ampersand, less-than, greater-than, double quote
   and apostrophe. TOTAL on arbitrary bytes. `Hermes_wiki.escape_html`
   is not exported, so this module carries its own rather than emit
   unescaped authored text. *)
val html_escape : string -> string

(* A complete JSON string LITERAL — the surrounding quotes included, so
   a caller cannot forget them. Escapes the double quote, the
   backslash, and every control character below 0x20 (as \b \f \n \r \t
   or \u00XX). No byte is ever DROPPED: a discarded carriage return
   would make the export disagree with the corpus about its own
   contents. TOTAL. *)
val json_string : string -> string

(* The plain-text INLINE renderer: it removes MARKUP and never removes
   TEXT. `[[Target#Frag]]` becomes `Target#Frag`, `![[x]]` becomes `x`,
   and every `*`, `` ` `` and `~` byte is dropped (so `**bold**` and
   `~~struck~~` both reduce to their text).

   TOTALITY CLAUSE: on a non-empty input it never returns "". Text that
   is ENTIRELY markup is returned verbatim, because a render that turns
   a heading into nothing has silently deleted a section — a document
   whose title is `**` is better shown as `**` than as a nameless
   heading, and [text_headings] can then read back every heading a page
   declares. *)
val inline_text : string -> string

(* ------------------------------------------------- HW.6.2.1 JSON API *)

(* THE LAW: THE API AND THE HTML RENDER THE SAME MODEL. The JSON is a
   PROJECTION of the built model value, never a second reading of the
   corpus — so it cannot drift from the pages the site serves.

   Three clauses, each separately checkable:

   1. Same PAGES. [json_slugs] equals the model's slugs, sorted. The
      API can neither invent a page the site does not serve nor hide a
      page the site does serve; a surface that answers for a different
      set of documents than the HTML is a second corpus wearing the
      first one's name.
   2. Same BYTES. Each page's `html` field carries `page.html`
      VERBATIM — the identical bytes the HTML surface serves, escaped
      for JSON and not re-rendered. Re-rendering here is exactly how
      the two surfaces would come to disagree.
   3. Same ANCHORS. Each page's `anchors` field equals
      `Hermes_wiki.anchors model slug`, so a consumer building a deep
      link lands where a reader clicking the same link lands.

   Anomalies travel too: an export that quietly dropped the model's
   anomaly list would report a healthy corpus that the builder does not
   believe is healthy. *)
val json : Hermes_wiki.model -> string

(* The page set the API exposes, sorted — clause 1 without a parser. *)
val json_slugs : Hermes_wiki.model -> string list

(* --------------------------------- HW.6.9.2 single-file HTML export *)

(* THE LAW: GLOBALLY UNIQUE ANCHORS. Concatenating N pages into one
   document makes every per-page anchor a potential collision — two
   pages with an `## Overview` each emit `id="overview"`, and in one
   document the second is unreachable while every link to it silently
   lands on the first. A single-file export whose links point at the
   wrong section is worse than no export, because it is confidently
   wrong.

   So uniqueness is established BY CONSTRUCTION, over the WHOLE
   concatenation, and not argued from the shape of the names:

   - Every id a page's render emits is scanned in EMISSION ORDER and
     given the qualified name `<slug>--<id>`; each page also gets a
     section anchor `page-<slug>`.
   - The qualified name is claimed in one global table, and a name
     already claimed is disambiguated with a `-2`, `-3` … counter
     (mirroring `Hermes_wiki`'s slug disambiguator). Uniqueness is
     therefore a property of the ALGORITHM, not of an injectivity
     argument about separators that a future block-id alphabet could
     invalidate.
   - Links are rewritten THROUGH THE SAME TABLE, keyed on
     (target page, fragment). A rename that moved an anchor and left a
     link behind is unrepresentable: there is one table and both sides
     read it.

   The scan is sound because the engine escapes authored text (a double quote
   becomes `&quot;`), so the closing quote of an `id="…"` or `href="…"`
   attribute is never an authored byte.

   THE SECOND LAW: LINK RESOLUTION IS PRESERVED, NOT MANUFACTURED. A
   link that resolves on the per-page surface still resolves here; a
   link that was already broken there is still broken here and is
   REPORTED by [dead_links]. The export never invents a target: a
   dangling `#section` silently rewritten to its page's top would turn
   a visible defect into a reader landing on the wrong text. Inter-page
   `<slug>.html` links become in-document `#page-<slug>` links; a link
   to a page outside the model is left VERBATIM, because an external
   href is not this document's to rewrite.

   Page order is by SLUG, ascending, stated here because
   `Wiki_ordering`'s authored order is not in this module's dependency
   closure and a silently different order would make two exports of one
   corpus differ. *)
val single_file_html : Hermes_wiki.model -> string

(* Every id the export emits, in emission order. The observation that
   makes uniqueness checkable against the document itself rather than
   against a re-derivation of it: [single_file_anchors] has no
   duplicate. *)
val single_file_anchors : Hermes_wiki.model -> string list

(* Every in-document link target the export emits (the `x` of
   `href="#x"`), in emission order, duplicates kept — a link emitted
   twice is two links a reader can follow. *)
val single_file_links : Hermes_wiki.model -> string list

(* The emitted in-document links that name no emitted anchor, sorted
   and deduped. EMPTY for a corpus with no broken anchors — that is the
   resolution law. Non-empty exactly where `Hermes_wiki.broken_anchors`
   already had something to say: this is the export DISCLOSING an
   inherited defect, never creating one. *)
val dead_links : Hermes_wiki.model -> string list

(* ---------------------------------- HW.6.9.3 plain-text export *)

(* THE LAW: A SECOND RENDER TARGET, SO THE SEPARATION OF STRUCTURE FROM
   PRESENTATION BECOMES TESTABLE. One renderer proves nothing about that
   separation — whatever it does is by definition "the render". Two
   render targets over ONE parse make the claim falsifiable: the text
   and the HTML are folds of the same `Wiki_ast.t`, so they can differ
   in presentation and MUST NOT differ in structure.

   The checkable form of "must not differ in structure":
     text_headings (page_text raw)
       = [ (level, inline_text text) | (level, text, _) <- headings ]
   for the page the raw body belongs to. The heading SEQUENCE and the
   heading LEVELS survive into a target that has no tags at all; if the
   text render lost, reordered or invented a section, this equation
   fails. Headings are encoded in the Sphinx text-builder convention —
   the text on its own line, underlined to its own length with `=`,
   `-`, `~`, `^` for levels 1–4 (`Hermes_wiki` caps heading level at
   4, and `Wiki_ast` caps it identically) — and [text_headings] is
   exactly that convention's reader.

   PRESENTATION, deliberately different: no tags, no ids, no anchors,
   no link hrefs. A fence's body is INDENTED and kept (a text render of
   a document containing code that omits the code is not a render of
   that document), a rule is a spaced `* * * *` (a run of one character
   would be read back as a heading underline), list items carry their
   marker, and table rows are indented `a | b`. Every emitted body line
   is either blank, indented, or carries a marker — so no body line can
   be mistaken for a heading underline. *)
val page_text : string -> string

(* The whole corpus as one text document, pages in SLUG order, separated
   by a rule and nothing else — no invented heading. So the corpus law
   is the per-page law summed:
     text_headings (plain_text m)
       = concat [ text_headings (page_text p.raw) | p <- pages by slug ]
   An export that inserted a title of its own would put a heading in the
   text render that no page declares. *)
val plain_text : Hermes_wiki.model -> string

(* The reader for the heading convention above: (level, text) in
   document order. TOTAL on arbitrary text — a document that is not a
   text render simply has no headings to report. *)
val text_headings : string -> (int * string) list

(* ---------------------------------------- HW.6.5.1 word count *)

(* THE LAW: FENCE-EXCLUDED, AND DETERMINISTIC.

   FENCE-EXCLUDED BY CONSTRUCTION. The count is a fold over
   `Wiki_ast.parse`, and the `Fence` arm contributes ZERO. It is not a
   line filter that a future construct could route around: a fence is
   excluded because the parser already decided it was a fence, and the
   same parse decides it for the renderer. Code is not prose, and a
   word count that grows when an author pastes a stack trace measures
   nothing an author recognises.

   A WORD is a maximal run of non-whitespace containing at least one
   alphanumeric byte, counted over the text AFTER markup is removed
   ([inline_text]) and after a block anchor is stripped
   (`Wiki_ast.block_anchor_split`, the same function both renderers
   use — a `^id` address is not a word the author wrote). A bare `-`,
   `|` or `>` is punctuation, not a word.

   DETERMINISTIC: no hash-table order, no locale, no randomness; the
   same bytes always yield the same number.

   ADDITIVE: [corpus_word_count] sums to exactly the per-page counts,
   so a total can be checked against its parts rather than trusted. *)
val word_count : string -> int

(* Per page, sorted by slug — one entry per page in the model. *)
val page_word_counts : Hermes_wiki.model -> (string * int) list

(* The corpus total. Equals the sum of [page_word_counts]. *)
val corpus_word_count : Hermes_wiki.model -> int

(* -------------------------------- HW.6.10.1 extlinks (shortening) *)

(* THE LAW: ONE DEFINITION PER NAME. A name defined twice is REFUSED,
   with every offending name reported — never resolved by "last one
   wins", which silently gives one author's `:issue:` to another
   author's tracker and cannot be detected by reading either
   definition. A table is either wholly admitted or wholly refused,
   because a partially-admitted table is a table whose meaning depends
   on which half you read.

   An UNDEFINED name is left VERBATIM. `:issue:`12`` with no `issue`
   definition stays as written: a text a reader can see and fix, rather
   than a link to nowhere. The escape hatch leaves a mark.

   A use inside a CODE FENCE is an example, not a use — the convention
   the rest of this corpus already keeps for wikilinks, tags and
   embeds.

   `%s` in the base and in the caption is the value's placeholder; a
   base without one takes the value APPENDED. Both the href and the
   link text are HTML-escaped, so a value carrying a double quote or a `<` becomes
   text and never markup. *)
type extlink = { name : string; base : string; caption : string }

(* [Ok defs] when every name is distinct; [Error names] with the
   duplicated names sorted and deduped. *)
val extlink_table : extlink list -> (extlink list, string list) result

(* The uses found in a body, in source order, fence-excluded, as
   (name, value) — including names the table does not define, so an
   undefined role is COUNTABLE and not merely invisible. *)
val extlink_uses : string -> (string * string) list

(* Rewrite every defined use into an `<a href=…>` anchor; leave every
   undefined use, and every use inside a fence, exactly as written.
   TOTAL: an unterminated `:name:`value` is text. *)
val expand_extlinks : extlink list -> string -> string

(* ------------------------- HW.6.3.7 client-side search index *)

(* THE LAW: OFFLINE SEARCH IS ONLINE SEARCH. The exported index returns
   EXACTLY what `Wiki_search.search` returns, for every query, over the
   same corpus — not "similar results", not "the same ranking usually".
   An offline index that answers a query differently is a second search
   engine that happens to ship with the first one's data, and the day
   they disagree is the day a reader stops trusting both.

   It is the SAME INDEX, not a second one. The postings are the online
   engine's OWN ANSWERS: for each token of the corpus vocabulary the
   export asks the injected [search] and stores what it says. There is
   no reimplementation of the scoring here to drift — headings weighing
   3, keywords 2, a description 1, fences excluded, all of it arrives
   already computed, because it arrives as an answer.

   INJECTED, NOT IMPORTED. [tokenise], [search] and [digest] are
   parameters (`Wiki_search.tokens`, `Wiki_search.search idx`,
   `Wiki_search.digest idx`). This module therefore has no dependency
   on the search library, stays pure, and — the load-bearing part — is
   structurally incapable of computing a score of its own.

   MULTI-TOKEN QUERIES are reconstructed with the online engine's own
   algebra: a page scores only if it carries EVERY query token, its
   score is the SUM over the query's token LIST (a repeated token
   counts twice, exactly as a scan of the corpus counts it twice), and
   ties break by slug ascending under score descending. A query with no
   tokens returns nothing.

   DIGEST-PINNED. [index_digest] carries the ONLINE index's digest into
   the export, and [index_json] emits it. An export taken against a
   changed corpus therefore announces itself: the pin moves, the diff
   is one line, and a stale client is visible rather than merely
   wrong. *)
type search_index

val search_index :
  tokenise:(string -> string list) ->
  search:(string -> (string * int) list) ->
  digest:string ->
  Hermes_wiki.model ->
  search_index

(* The tokens with at least one hit, sorted. A token the corpus
   contains only inside a fence has no hit and is not stored — the
   online engine having already excluded it is the whole reason. *)
val vocabulary : search_index -> string list

(* One token's postings: (slug, score), the online engine's answer
   verbatim. [] for an unknown token. *)
val postings : search_index -> string -> (string * int) list

(* The offline query. THE differential: this must equal
   `Wiki_search.search idx q` for every q. *)
val offline_search : search_index -> string -> (string * int) list

(* The online index's digest, carried through the export unchanged. *)
val index_digest : search_index -> string

(* The pure data a client ships: the digest pin and the sorted
   postings, as JSON. Byte-identical for an unchanged corpus. *)
val index_json : search_index -> string

(* The canonical serialisation [index_json] is a rendering of — one
   line per (token, slug, score), sorted. Mirrors
   `Wiki_search.canonical`: a digest is only meaningful over a
   canonical form. *)
val index_canonical : search_index -> string
