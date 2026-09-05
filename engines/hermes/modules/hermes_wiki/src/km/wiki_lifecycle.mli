(* The lifecycle / governance laws — six register rows that share one
   posture: each of them is a place where the system is tempted to INVENT
   a fact it does not have, and each law is the refusal to do it.

     HW.8.1.5  Surface last_update          a date is READ, never authored
     HW.8.2.5  Link check (external URLs)   unchecked is not passing
     HW.8.3.1  Page templates               an unfilled slot is an error
     HW.8.5.3  Ontology / concept model     the vocabulary is checkable data
     HW.1.2.6  slug frontmatter override    an escape hatch leaves a mark
     HW.1.3.9  description field            declared, else derived, else ""

   PURE, and deliberately so: no filesystem, no clock, no network, no
   Unix. Every fact this module reasons about arrives as an argument.
   That is not an aesthetic choice — for four of these six rows the
   forbidden effect IS the failure mode. A module that could read the
   clock would answer "when was this last updated?" with today; a module
   that could open a socket would answer "is this link alive?" while the
   render waits on DNS. Neither answer is worth having.

   TOTAL at the edges: an absent field, a malformed date, an empty
   corpus, a template with no placeholders, a string that is not a URL —
   each has a defined value. Nothing here raises. *)

(* ==================================================== HW.8.1.5 last_update

   The row's claim: "read from git, NEVER authored (R16)".

   A timestamp is EVIDENCE about when a fact was established, so a
   fabricated one is not a cosmetic defect — it is a forged receipt, and
   worse than no receipt at all because it looks authoritative. The type
   below therefore has three constructors and not two: the absence of a
   date is a first-class answer ([Unknown], rendered "unknown"), never
   silently replaced by the day the page happened to be built. *)

type stamp =
  | Known of string      (* a well-formed ISO date: YYYY-MM-DD *)
  | Malformed of string  (* present but not a date — preserved VERBATIM,
                            because the author must see what they wrote;
                            a normalised guess would erase the evidence *)
  | Unknown              (* absent. The honest answer. *)

(* WHERE the date came from, carried in the result rather than dropped:
   "read from git, never authored" is only auditable if a reader can tell
   the two apart after the fact. *)
type origin =
  | From_git          (* the substrate (HW.8.1.4): git is the record *)
  | From_frontmatter  (* a DISCLOSED authored fallback, not an equal *)
  | Absent

type last_update = { stamp : stamp; origin : origin }

(* Shape only: four digits, '-', two, '-', two, with month in 01..12 and
   day in 01..31. A shape check, not a calendar — this module knows
   nothing about leap years and does not pretend to. Anything else is
   [Malformed]; the empty string is [Unknown]. TOTAL. *)
val parse_date : string -> stamp

(* Git DOMINATES frontmatter, because one of them is a record and the
   other is a claim. Two consequences worth stating:

   - a git answer that is malformed stays [Malformed] and does NOT fall
     back to frontmatter. Falling back would let an authored date quietly
     paper over a broken substrate, which is exactly the substitution
     R16 forbids;
   - [~git:None] and [~git:(Some "")] both mean "git said nothing", and
     only then is the authored value consulted.

   Both absent yields [{ stamp = Unknown; origin = Absent }]. *)
val last_update : git:string option -> frontmatter:string -> last_update

(* The surface form. [Unknown] renders "unknown" — a word, deliberately,
   so that a reader who sees it cannot mistake it for a date. *)
val render_stamp : stamp -> string

(* The corpus surface: one line per document, from (slug, git,
   frontmatter) triples, sorted so a diff of two runs is a diff of the
   corpus. Each line discloses its origin, so "how many of our pages have
   an authored date?" is answerable by counting. *)
val last_update_report : (string * string option * string) list -> string list

(* ============================================== HW.8.2.5 external links

   The row's claim: "a SEPARATE build; render unaffected by network
   state".

   This is an EXTRACTOR plus a CLASSIFIER, and there is no third part.
   Nothing here opens a connection; reachability arrives as injected
   evidence gathered by some other process at some other time. That
   separation is what makes the claim true: the render cannot be slowed,
   reordered or failed by the state of someone else's web server.

   The law that carries the row is about the THIRD verdict. A URL for
   which no evidence was supplied is [Unchecked] — not [Live], not
   [Broken]. Calling it [Live] would turn "we did not look" into "it is
   fine", which is the R2 failure in its purest form; calling it [Broken]
   would manufacture a defect out of our own inaction. A skip is
   disclosed and counted. *)

(* Fence-aware and inline-code-aware extraction of http/https URLs from a
   markdown body: bare text, `[label](url)` and `<url>` autolinks.

   CODE IS NOT PROSE. A URL inside a ``` fence or inside `backticks` is
   an EXAMPLE of a URL, not a reference to one. This is not a
   hypothetical refinement: the corpus has twice been reported to contain
   dead links that were entirely examples quoted in documentation, and
   both times the report was the bug.

   Trailing sentence punctuation (`.,;:!?`) is stripped, because
   "see https://example.org." ends a sentence and does not name a host
   called `org.`. Sorted and deduped: a URL cited twice is one link to
   check, and the order is the same on every run. TOTAL — a body with no
   URLs, or no text at all, yields []. *)
val external_urls : string -> string list

(* Injected evidence: what some external checker actually observed. This
   type deliberately cannot express "probably fine". *)
type probe =
  | Reachable
  | Dead of string  (* the observed reason, verbatim from the checker *)

type verdict =
  | Live of string
  | Broken of string * string  (* url, reason *)
  | Unchecked of string        (* no evidence was supplied. NOT a pass. *)

(* One verdict per URL, in the order given, and exactly that many:

   - a URL with no entry in [evidence] is [Unchecked], full stop;
   - evidence for a URL that is NOT in the list is IGNORED, by law. The
     evidence set is a cache and may legitimately cover the whole corpus
     or a previous run; the verdict list answers a question about THIS
     document, and letting a stray cache entry add a link to it would
     make the answer depend on the cache's history.

   A repeated key in [evidence] takes its first binding. *)
val classify : evidence:(string * probe) list -> string list -> verdict list

type link_summary = { live : int; broken : int; unchecked : int }

(* The counts, and the reason [unchecked] is a field and not a footnote:
   a link report whose headline is "0 broken" is a lie when the other
   number is "417 unchecked". Both are always printed. *)
val summarise : verdict list -> link_summary

(* ============================================== HW.8.3.1 page templates

   The row's claim: "deterministic; computed fields are kernels".

   Instantiating a template is a pure text function over a body with
   DECLARED placeholders. Determinism is the whole value: the same
   template and the same fills produce the same bytes, forever, with no
   date, no counter and no environment in between.

   Two errors, and neither may be swallowed. A placeholder the fill set
   does not answer must NOT reach the page as a literal `{{x}}` — that
   ships a broken page that looks like a rendering bug rather than a
   missing input. A key in the fill set the template does not declare
   must NOT be silently dropped — the author believes they set something,
   and they did not. Both are named, and both are collected: a caller
   fixing a template wants the whole list, not the first item of it. *)

type template = {
  name : string;
  body : string;
  placeholders : string list;  (* DECLARED: sorted, deduped, as scanned *)
}

(* Scans `{{name}}` occurrences to declare the template's placeholders.
   Fence-aware and inline-code-aware for the same reason as the link
   extractor: a template that DOCUMENTS the placeholder grammar in a
   fenced block is not thereby requiring a fill for it. A fenced
   `{{x}}` is an example — it is not declared, it is never substituted,
   it stays literal in the output, and it is not an error.

   `{{}}` (an empty name) is not a placeholder; `{{x` is unterminated
   text. Both stay literal and neither raises. *)
val template : name:string -> string -> template

type fill_error =
  | Unfilled of string             (* declared, not supplied *)
  | Unknown_placeholder of string  (* supplied, not declared *)

val show_fill_error : fill_error -> string

(* [Ok body] only when the fill set matches the declared set EXACTLY;
   otherwise [Error errors] with every fault, deterministically ordered
   (unfilled before unknown, each sorted). Consequences worth naming:

   - a template with no placeholders and an empty fill set returns its
     body BYTE-IDENTICAL — instantiation is the identity when there is
     nothing to instantiate;
   - a repeated key takes its first binding;
   - on [Error] nothing is rendered at all. A partially substituted page
     is the one output that must never exist, because it is the one a
     reviewer would mistake for a finished one. *)
val instantiate : template -> (string * string) list -> (string, fill_error list) result

(* ================================== HW.8.5.3 ontology / concept model

   The row's claim: "R12: component and edges in the SAME commit".

   The concept model as CHECKABLE DATA, not prose. A note explaining the
   vocabulary drifts from the corpus the day after it is written and
   nothing notices; a vocabulary the corpus is checked against cannot.

   The terms are taken verbatim from the `meta` comments in
   `hermes_wiki.mli` — there is ONE controlled vocabulary in this system
   and this module reads it, it does not compete with it. *)

type axis =
  | Ktype       (* artifact role:      atomic | moc | source | journal *)
  | Maturity    (* lifecycle:          seed | incubating | evergreen | archived *)
  | Status      (* editorial:          draft | published | flagged_for_review *)
  | Ntype       (* discourse type:     note | question | claim | evidence | decision | reference *)
  | Visibility  (* HW.1.4.1:           draft | unlisted | listed *)
  | Domain      (* "a single controlled term" — controlled by the corpus,
                   not by this module. An OPEN axis. *)

val axes : axis list
val axis_name : axis -> string

(* The declared terms, or [] for an axis that is OPEN. [] is not
   "unknown vocabulary" — it is the assertion that this axis admits any
   term, which is why [is_open] exists rather than callers testing for
   the empty list and guessing what it meant. *)
val vocabulary : axis -> string list
val is_open : axis -> bool

(* The RELATION the axes stand in: they are orthogonal — the concept
   model is the product of these vocabularies, and no combination is
   forbidden — but they are not equally obligatory. The PKM schema
   (HW.1.3.16) requires ktype, maturity and domain; the other three carry
   honest defaults and an unset value is legitimate. *)
type requirement = Required | Optional

val requirement : axis -> requirement

type value_verdict =
  | Unset          (* "" — NOT this module's finding. See below. *)
  | In_vocabulary
  | Open_term      (* any value on an open axis *)
  | Outside        (* declared closed, and this is not one of the terms *)

val classify_value : axis -> string -> value_verdict

(* The value an axis reads off a document's metadata. Exhaustive over
   [axis], so a new axis cannot be added without answering this. *)
val axis_value : Hermes_wiki.meta -> axis -> string

(* THE VERDICT the row must add: corpus values that fall OUTSIDE the
   declared vocabulary, one sorted line each.

   An UNSET value is not reported here. That is deliberate and it is not
   an omission: a missing required field is already
   [Hermes_wiki.schema_gaps]' verdict, and a second reporter of the same
   fact is how two counts of the same defect end up disagreeing in the
   same dashboard. This module answers a question nothing else answers —
   the value is present, and it is not a term we recognise. *)
val vocabulary_gaps : Hermes_wiki.model -> string list

(* ========================================== HW.1.2.6 slug override

   The row's claim: "explicit slug wins; still injective".

   Two halves, and the second is the one that is usually dropped. An
   explicit slug WINS — that is what an override is for. But a URL is an
   identity, so the resolution must stay INJECTIVE, and two documents
   claiming the same explicit slug is a contradiction between two
   authors. It is REPORTED, never resolved: picking a winner by corpus
   order would hand one author the other's URL silently, and neither of
   them would ever find out.

   An override is an escape hatch, and an escape hatch leaves a mark.
   Every accepted declaration is countable through [slug_overrides] —
   including the ones that changed nothing, because "how many pages
   override their slug?" is a question about governance, not about
   diffs. *)

type slug_claim = {
  path : string;
  declared : string option;  (* the frontmatter claim, if any *)
  derived : string;          (* what the engine derived from the path *)
}

type slug_source =
  | Declared_slug      (* the override took effect *)
  | Derived_slug       (* no claim was made *)
  | Declared_malformed (* a claim was made and could not be used *)

type slug_resolution = { path : string; slug : string; source : slug_source }

(* A declared slug is normalised through [Hermes_wiki.slugify] — the same
   function the engine derives with, so an override cannot introduce a
   key shape the resolver could never produce.

   A claim that normalises to "" (empty, whitespace, or punctuation only)
   is [Declared_malformed]: the derived slug stands, and the failed
   attempt is reported. Falling back silently would leave an author
   convinced their override worked. TOTAL. *)
val resolve_slug : slug_claim -> slug_resolution
val resolve_slugs : slug_claim list -> slug_resolution list

(* The mark. One sorted line per document that made a claim — accepted or
   malformed — so the escape hatch is always countable. *)
val slug_overrides : slug_claim list -> string list

(* Injectivity, checked. Any final slug held by more than one document,
   one sorted line each, and the two cases are NOT the same verdict:

   - "explicit slug collision: …" — at least one of the colliding
     documents claimed this slug. A DEFECT: an author asserted an
     identity that is not theirs alone, and no machine may choose
     between them.
   - "derived slug collision: …" — neither claimed it; both merely
     derived it from their filenames. This mirrors the engine's own
     resolved-collision NOTICE (Hermes_wiki disambiguates these by
     prefixing), and is reported here for completeness rather than as a
     new fault.

   A [Declared_malformed] document collides as a derived one, because no
   explicit slug is in effect for it. *)
val slug_collisions : slug_claim list -> string list

(* ============================================ HW.1.3.9 description

   The row's claim: "free text; feeds ranking".

   Three-valued, like every other lookup in this module: declared, else
   derived from the body's first paragraph, else EMPTY with [No_desc].
   The third case is the point — a page with nothing to say about itself
   says nothing, and does not get a sentence invented for it. *)

type desc_origin =
  | Declared_desc  (* the author wrote it *)
  | Derived_desc   (* taken from the body's first paragraph *)
  | No_desc        (* nothing to take. text = "" *)

type description = { text : string; origin : desc_origin; truncated : bool }

val max_description : int

(* [body] is the document BODY — frontmatter already removed by the
   engine. This module does not parse frontmatter (there is exactly one
   frontmatter parser in this system, in `hermes_wiki.ml`, and a second
   one would diverge from it), so a raw document passed here would have
   its own header read as prose. Stated rather than defended against,
   because a silent guard would hide the caller's mistake.

   Derivation skips fenced blocks, blank lines and headings, then takes
   the first run of consecutive prose lines joined by a single space.

   Truncation at [max_description] is a hard byte cut with [truncated]
   set — no ellipsis, because the flag is the disclosure and an inserted
   character would corrupt the very bytes the field is supposed to
   carry. *)
val describe : declared:string -> body:string -> description

(* Lowercased alphanumeric terms of the description, sorted and deduped. *)
val description_terms : description -> string list

(* "Feeds ranking" — ADDITIVE, never a replacement. [body_terms] arrives
   from whatever tokenizer the search surface actually uses and passes
   through UNCHANGED, so [body_terms] is always a subset of the result.
   A description can therefore boost a page but can never hide it from a
   search for words that are in its body — an override that could
   suppress the document's own text would be a censorship knob, not a
   ranking hint. *)
val ranking_terms : description -> body_terms:string list -> string list
