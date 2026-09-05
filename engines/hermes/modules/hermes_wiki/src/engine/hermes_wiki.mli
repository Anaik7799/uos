(* The Hermes wiki/Zettelkasten core: the ported heart of the zigvm
   docs_wiki model (migration wave W1 core; the full 91-law port is the
   roadmap in docs/hermes/wiki-zk-migration-plan.md).

   PURE: build takes (path, content) pairs; read_tree is the only IO and
   lives at the edge. Laws pinned by test_hermes_wiki include the zigvm
   domain law fst back_ctx == backlinks. *)

type meta = {
  id : string;              (* frontmatter id, else deterministic from slug *)
  status : string;          (* draft | published | flagged_for_review *)
  ntype : string;           (* the DISCOURSE vocabulary, closed:
                               note | question | claim | evidence | decision |
                               reference | policy | playbook.
                               `policy` and `playbook` were admitted
                               deliberately (see the parse site) — this
                               comment had not followed them, and
                               Wiki_lifecycle took its vocabulary from
                               here verbatim, so the documented set and
                               the enforced set had quietly diverged. *)
  last_verified : string;   (* ISO date the fact was confirmed, or "" *)
  verified_by : string;     (* agent | human | "" *)
  next_review : string;     (* decay signal: when a re-check is due, or "" *)
  has_frontmatter : bool;   (* did the file carry an explicit --- block *)
  allow_example_links : bool;  (* audit exemption for notes quoting the grammar *)
  generated : bool;
  migrated_from : string option;
  (* PKM schema (docs/hermes/specs/2026-08-09-pkm-longterm-architecture.md §3):
     two NEW AXES beside the discourse type and editorial status, plus the
     archival fields. Absent = "" or [] — honest defaults, never fabricated. *)
  aliases : string list;    (* additional resolver keys (HW.1.2.7) *)
  ktype : string;           (* artifact role: atomic | moc | source | journal *)
  maturity : string;        (* seed | incubating | evergreen | archived *)
  domain : string;          (* single controlled term *)
  topics : string list;     (* granular document-level tags *)
  links : string list;      (* DECLARED parent/child UIDs only — I3: the body
                               graph stays derived, never stored *)
  created : string;         (* R16: read from git/env, never invented *)
  visibility : string;      (* HW.1.4.1: draft | unlisted | listed; "" = unset *)
  orphan : bool;            (* HW.6.8.2: a DISCLOSED entry point. The page
                               declares that no navigation tree places it
                               and that this is deliberate — the escape
                               hatch that leaves a mark, never a silent
                               exemption. *)
  default_role : string;    (* HW.2.7.2: what a bare `span` means — "code"
                               (identity, the default) or "any" (a checked
                               reference). Page-level config, not schema. *)
  (* HW.1.3.10–13: the frontmatter that decides ORDER and LABEL. Parsed
     here so the corpus has one frontmatter parser; the laws that give
     them meaning live in Wiki_ordering. None of the three is part of
     the required PKM schema — declaring an order is optional, and a
     corpus that declares none still has a total order. *)
  hide_toc : bool;          (* HW.1.3.15: PRESENTATION only. It suppresses the
                               contents nav and nothing else — the heading
                               anchors are untouched, so an inbound fragment
                               link into a page whose author hid the contents
                               list still resolves. *)
  keywords : string list;   (* HW.1.3.10: search terms ADDITIVE to the body's,
                               never a replacement — a keyword cannot hide a
                               page from a search for its own words. *)
  sidebar_position : int option;  (* HW.1.3.11: explicit position. A malformed
                               value CLAMPS to None; a typo must not raise. *)
  sidebar_label : string;   (* HW.1.3.13: label ?? title. "" = unset, which is
                               NOT the same as an empty label. *)
  slug_claim : string;      (* HW.1.2.6: a DECLARED slug. It WINS over the
                               derived one, and every claim leaves a
                               countable mark — an escape hatch that does
                               not is indistinguishable from a bug. "" =
                               unset. Wiki_lifecycle holds the laws. *)
  description : string;     (* HW.1.3.9: the declared summary, "" = unset.
                               Feeds ranking ADDITIVELY — a description
                               can boost a page, never hide it from a
                               search for its own body words. *)
}

type page = {
  path : string;
  slug : string;
  title : string;
  group : string;           (* first directory under docs/hermes, "" if none *)
  meta : meta;
  html : string;
  outlinks : string list;   (* every [[target]], resolved-or-not, as slugs *)
  mentions : string list;   (* slugs whose TITLE appears here without a link *)
  typed : (string * string) list;  (* [[T|@rel]] -> (slug, rel) *)
  tags : string list;       (* #tags outside code fences *)
  headings : (int * string * string) list;  (* level, text, anchor slug *)
  backlinks : string list;  (* slugs of pages linking here *)
  back_ctx : (string * string) list; (* (source slug, citing line) *)
  frag_refs : (string * string) list; (* (target slug, fragment anchor) refs made here *)
  raw : string;
}

type model = {
  pages : page list;
  anomalies : string list;
  include_failures : string list;
      (* HW.9.2.1: computed inside build, the only place holding the
         injected reader — read it through [include_gaps]. *)
}

val slugify : string -> string

(* [read_source] is HW.9.2.1's injected reader: a repo-relative path to
   its bytes. STILL PURE — build never touches the filesystem itself, and
   the default reader resolves NOTHING, so an include without an injected
   reader fails closed and says so rather than rendering empty. *)
val build : ?read_source:(string -> string option) -> (string * string) list -> model
val page : model -> string -> page option
(* Anomalies split by consequence: a DEFECT means the corpus is wrong
   (an unknown discourse type); a NOTICE records something the builder
   resolved (a slug collision). The render and serve drivers refuse on
   defects and print notices — refusing on a notice would make a
   correctly-handled collision block the site. *)
val defects : model -> string list

(* HW.3.4.2: the anchors a page emits — every id present in its render. *)
val anchors : model -> string -> string list

(* HW.3.4.3: fragment references whose document resolves but whose anchor
   does not. A diagnosis DISTINCT from a dead link, because the fix is
   different: a dead link wants a target, a dead fragment wants a heading. *)
val broken_anchors : model -> string list

(* HW.3.7.2: references whose target key is CONTESTED at one precedence
   tier — two pages claiming the same identity key, or (with no identity
   claim) two pages claiming the same alias. Reported at the USE site,
   where the reader is actually harmed; |resolve_any(x)| = 0 stays a dead
   link — the two verdicts are DISTINCT by construction. An alias never
   shadows an identity key (HW.1.2.7), and an ARCHIVED page never
   contests a living one. Deterministic sorted lines. *)
val ambiguous_refs : model -> string list

(* HW.3.7.3 nitpicky mode: doc references that resolve at NO tier —
   living, archived or alias. Term references are HW.3.7.4's business
   (the kind law keeps the verdicts separate), fragments are
   broken_anchors', and a !suppressed reference is exempt BY DESIGN.
   allow_example_links pages are exempt as everywhere. Sorted lines. *)
val unresolved_refs : model -> string list

(* HW.3.7.6/3.7.3: the DISCLOSED per-reference opt-outs — every
   [[!target]] in the corpus, one sorted line each. The escape hatch
   leaves a mark: never warned, always countable. *)
val suppressed_refs : model -> string list

(* HW.3.7.4 — the glossary: a page with "glossary" among its topics
   defines one term per level-2+ heading; the term key is the slugified
   heading, its location the page and heading anchor. Sorted, deduped. *)
val glossary_terms : model -> (string * (string * string)) list

(* Terms used and undefined — the controlled vocabulary's enforcement.
   [[term:x]] resolving to no glossary heading, one sorted line each;
   !suppressed and allow_example_links exempt as everywhere. The verdict
   is DISTINCT from unresolved_refs by the kind law. *)
val term_gaps : model -> string list

(* HW.2.6.3 — the back-of-book index: entries authored at the point of
   relevance as `<!-- index: term -->`, `<!-- index: term; subterm -->`
   or `<!-- index: see: term -> target -->`, compiled corpus-wide as
   (term, subterm, slug, nearest-preceding-heading anchor), sorted.
   A see-entry's subterm is "see: target". Fence-aware. *)
val corpus_index : model -> (string * string * string * string) list

(* see-targets must EXIST as concrete entries — each miss, one line. *)
val index_violations : model -> string list

(* HW.9.2.1 — includes that did not resolve: page, path and the named
   reason, one sorted line each. The dual of the denotation law: a
   failed include is LOUD, never a quietly empty block. *)
val include_gaps : model -> string list

(* HW.2.6.6 — fence options that do not hold: `emphasize` outside
   [1..lines(body)]. One sorted line each. *)
val fence_option_gaps : model -> string list

(* HW.9.3.1 — the doctest builder's core: a fence whose info tokens
   include "doctest" carries `> input` markdown lines and expected
   rendered-HTML lines; the render of the input must equal the expected
   BYTES. A mismatch is DOCUMENTATION DRIFT — it may block credit,
   never deny it (R5). Evaluation is pure (empty resolver). *)
val doctest_drift : model -> string list

(* The four resolver keys a page registers (slug, title, basename,
   title-minus-ordinal) in registration order — one source of truth for
   consumers that must resolve exactly as build does (Dep_sheaf). *)
val resolver_keys : page -> string list

(* Alias keys (slugified), registered in a SECOND pass after every page.s
   identity keys — an alias can never shadow a slug, title or basename. *)
val alias_keys : page -> string list

(* PKM schema conformance (docs/hermes/specs/2026-08-09-pkm-longterm-
   architecture.md §3): documents missing a required field, one line per
   gap. Notices, never defects — report first, ratchet later. *)
val schema_gaps : model -> string list

(* A [[Doc#Section]] target with its fragment removed; identity otherwise. *)
val strip_fragment : string -> string

(* Fence-aware wikilink targets of a RAW body — what a render observes,
   before allow_example_links curation strips graph edges. *)
val raw_link_targets : string -> string list
val notices : model -> string list

val moc : model -> (string * string list) list

(* [resolve_term] is the GLOSSARY space (HW.3.7.4) — a term key to a
   complete href. Absent = empty glossary: every term honestly missing,
   never a doc-space fallback (the kind law). [default_role] is
   HW.2.7.2 — absent or "code" is the identity. *)
val render_markdown :
  ?default_role:string ->
  ?resolve_term:(string -> string option) ->
  ?read_source:(string -> string option) ->
  ?default_lang:string ->
  resolve:(string -> string option) ->
  string ->
  string

(* The ORACLE for HW.2.0.1: the streaming line machine the AST path
   replaced. Kept and permanently exercised — its behaviour IS the
   specification, and `test_wiki_ast` compares the two over the whole
   corpus. Not for general use; call render_markdown. *)
val render_line_machine :
  ?read_source:(string -> string option) ->
  ?default_lang:string ->
  resolve:(string -> string option) ->
  string ->
  string

(* The filesystem reader HW.9.2.1's includes want, at the IO EDGE where
   every other read lives: repo-relative path -> bytes, None if absent
   or unreadable. Tools pass it to [build]; the engine never calls it
   on its own. *)
val read_source_file : string -> string option

(* Raised when the corpus cannot be DETERMINED — git refused, or a
   tracked path could not be read. Distinct from an empty corpus on
   purpose: a tool that cannot tell those apart will happily re-pin a
   gate artifact to nothing and exit 0. Callers must not catch this and
   continue. *)
exception Corpus_unreadable of string

(* IO edges. [read_tracked] is the CORPUS (zigvm §3: git ls-files, so an
   untracked note is invisible until it is committed); [read_tree] walks
   the filesystem and is kept for tooling that must see uncommitted work. *)
val read_tracked : string -> (string * string) list
val read_tree : string -> (string * string) list

(* HW.4.1.5 — the INVERSE of a typed edge: who points at this page, and
   with what relation. The outgoing direction lives on the page itself
   (`typed`) and now reaches the render as a `data-rel` attribute; this
   is the other direction, which the model could not express at all
   before. "Rendered both directions" is not satisfied by an edge only
   its author can see: a claim needs to know what supports it, not only
   what it supports. Sorted, deduped. *)
val typed_backlinks : model -> string -> (string * string) list
