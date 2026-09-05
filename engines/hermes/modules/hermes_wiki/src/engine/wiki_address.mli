(* THE ADDRESSING FAMILY — five laws about how a written name reaches a
   thing, and about what happens when it cannot.

     HW.3.9.1  reference domains        — cross-domain collision unrepresentable
     HW.3.8.1  reference inventory      — publish exactly what the resolver reaches
     HW.3.10.1 substitutions            — one definition; undefined => diag
     HW.3.10.2 include (whole document) — acyclic, depth-bounded
     HW.3.2.3  {#custom-id} heading ids — anchor o retitle = anchor

   They are one family because they are one question asked five ways:
   given a name written by an author, WHICH thing does it denote, and how
   does the corpus say so out loud when the answer is not unique, not
   present, or not terminating.

   PURE. No filesystem, no clock, no global state: the whole-document
   include takes its reader INJECTED (`~read`, exactly as
   `Wiki_include.slice` does), so every law below is a unit test rather
   than a fixture on disk.

   TOTAL AT THE EDGES. Every function here is defined on every string.
   A malformed marker is preserved VERBATIM and RECORDED — never dropped
   and never raised. Losing an author's bytes to a typo in a marker is
   the worst failure mode this family can have, because the author is the
   only one who still knows what the text said.

   CODE IS NOT PROSE. Every scanner here is fence-aware AND inline-
   backtick-aware from the first line: a `{#id}`, a `{{name}}` or an
   `<!-- include: ... -->` inside a fence or between backticks is an
   EXAMPLE OF THE GRAMMAR, not a use of it. This is not a hypothetical —
   the same confusion in this corpus once reported 25 phantom embeds and
   10 phantom dead links, in documents that were describing the syntax.

   DETERMINISTIC. Every list this module returns is sorted (or in
   document order, which is equally stable); no hash-table order ever
   escapes.

   MIRROR, NOT REINVENTION (R14, and see docs/hermes/zigvm-overlap-map.md):
   the address grammar is `Wiki_ref`'s ONE payload grammar with a domain
   axis composed onto its kind axis — this module never re-parses a
   reference, it calls `Wiki_ref.parse`. The expansion machinery
   (path-not-visited-set cycle breaking, a REPORTED depth bound, a loud
   marker for every failure) is `Wiki_transclude.expand`'s algebra
   applied to two other markers. *)

(* ------------------------------------------------------ HW.3.9.1 domains

   A DOMAIN is the namespace a name is written in. Sphinx introduced
   domains because one corpus holds several kinds of named thing and
   their names collide: a journal entry and a Zettelkasten note may both
   be called `index` and neither is wrong.

   THE LAW: A CROSS-DOMAIN COLLISION IS UNREPRESENTABLE. An address
   carries its domain, resolution filters on it, and therefore a
   domain-qualified name can NEVER be answered by an object of another
   domain. It does not resolve the collision by preferring one domain —
   it makes the collision impossible to express, which is the only form
   of "prevented" that cannot rot.

   The set is CLOSED and lowercase, exactly like `Wiki_ref`'s role set,
   and for the same reason: `[[re: subject]]` must stay a plain target
   that happens to contain a colon, or the grammar eats real titles.

   The four domains are the corpus's own strata (R16): `wiki`, `zk`,
   `journal`, `spec`. Everything else under the corpus root is an
   ORDINARY PAGE and therefore `wiki` — R16 says so in prose, and
   [domain_of_path] is that sentence made mechanical. *)

type domain = Wiki | Zk | Journal | Spec

(* Every domain, in a fixed order — a structure test can iterate it, so a
   new domain that ships without a law fails rather than hides. *)
val domains : domain list

val domain_name : domain -> string

(* The closed lowercase set, as a partial function. [None] for anything
   else, which is what keeps `re:` and `Doc:` out of the grammar. *)
val domain_of_name : string -> domain option

(* The domain a document lives in, from its path alone: the parent
   directory name, read exactly as the engine's own `group_of` reads it,
   so a page's domain and its group can never disagree. Unknown parents
   are [Wiki] — R16's "everything else joins the same graph as an
   ordinary page". *)
val domain_of_path : string -> domain

(* THE ADDRESS: `Wiki_ref`'s payload with a domain qualifier.

     [!] [domain:] [doc:|term:] target[#fragment] [ |display | |@rel ]

   The domain qualifier composes with the role in EITHER order —
   `[[zk:doc:x]]` and `[[doc:zk:x]]` are one address — because there is
   one grammar and this is a projection of it, not a second parser.
   [None] is an UNQUALIFIED address: it searches every domain and may
   therefore return several candidates, which is ambiguity at the
   reference site, never a hidden preference (the `Wiki_ref.Any` rule,
   inherited rather than restated). *)
type address = {
  domain : domain option;
  reference : Wiki_ref.t;
}

(* TOTAL: every payload parses. An unknown qualifier is not a domain, it
   is part of the target — so a title containing a colon survives. *)
val parse : string -> address

(* The written form, `[[...]]` and all, exactly as [Wiki_ref.to_wiki]
   emits it: `to_wiki (parse p) = "[[" ^ p ^ "]]"` on canonical
   (already-trimmed) forms, in either qualifier order. *)
val to_wiki : address -> string

(* ---------------------------------------------------- HW.3.8.1 inventory

   An INVENTORY is the corpus's published address book: every name that
   can be written, and the thing it reaches. Sphinx publishes one
   (`objects.inv`) so that a SEPARATE project can link into this one
   without guessing at its URLs.

   THE LAW, IN BOTH DIRECTIONS: THE INVENTORY AGREES WITH THE RESOLVER.

     - SOUND: every published entry resolves, and resolves to the slug
       the entry names. An inventory that lists an address the resolver
       cannot reach is worse than no inventory at all, because a consumer
       has no way to discover that it was lied to — the link simply dies
       in someone else's site.
     - COMPLETE: every key the resolver can reach is published. A missing
       entry is a silently unlinkable page.

   Both directions are proved mechanically in the suite against a BUILT
   model — the entry's claim is checked against the engine's own rendered
   href, not against this module's opinion of it.

   IT IS A FUNCTION, NOT A RELATION. At most one entry per (kind, key):
   the engine's resolver registers first-wins across three tiers (living
   identity > archived identity > alias), and the inventory publishes the
   WINNER, because the winner is what a reader actually reaches. The
   losers are not addresses; they are `ambiguous_refs`' business, and
   reporting them here as though they were reachable is precisely the
   lie the soundness direction forbids.

   ROOT-RELATIVE. Every location begins with `/` and is a site path, not
   a filesystem path and not a URL with a host: a consumer joins it to
   the base it already knows. A relative location silently means
   something different in every directory it is read from.

   DIGEST-PINNED. [inventory_digest] is a digest of the inventory BYTES,
   and those bytes are sorted, so it is invariant under corpus order
   wherever the resolver itself is (i.e. wherever no key is contested).
   A consumer pins the digest; a change to the address space is then a
   changed pin, which is a reviewable diff instead of a surprise. *)

type entry = {
  edomain : domain;
  ekind : Wiki_ref.kind;      (* Doc or Term — never Any: an inventory
                                 entry is a thing, and every thing has a
                                 kind. Any is a question, not an answer. *)
  ekey : string;              (* the written name, slugified as the
                                 engine slugifies it before lookup *)
  eslug : string;
  eanchor : string option;    (* a term IS a location: page + heading *)
}

(* The published address space of a built corpus: the resolver's winning
   registrations (four identity keys per page, then aliases) as Doc
   entries, and the glossary space as Term entries. Sorted, deduped. *)
val entries_of_model : Hermes_wiki.model -> entry list

(* Root-relative site location. Always `/slug.html`, plus `#anchor` when
   the entry is a term. *)
val location : entry -> string

(* The publishable bytes: a version line, then one sorted tab-separated
   line per entry. Sorted, so the bytes are a function of the entry SET
   and not of the order it was assembled in. *)
val inventory : entry list -> string

(* The pin: a digest of exactly those bytes. *)
val inventory_digest : entry list -> string

(* RESOLUTION, kind-scoped and domain-scoped at once:

     kind(resolve_k(x))     = k   for k <> Any   (inherited: Wiki_ref)
     domain(resolve_d(x))   = d   for d <> None  (HW.3.9.1)

   An unqualified address is the UNION over domains, and an [Any] kind
   the union over kinds. A domain-qualified address that finds nothing
   returns the empty list — it NEVER falls back to another domain, which
   is the whole point of writing the qualifier. *)
val resolve : entry list -> address -> entry list

(* ----------------------------------------- HW.3.10.1/3.10.2 expansion

   One outcome type for both expanders, mirroring `Wiki_transclude.outcome`
   because the failure algebra is identical: the text always comes back,
   and every way it could have gone wrong is a separate, sorted, named
   list. Nothing here is ever silent. *)

type outcome = {
  text : string;              (* the expanded body — ALWAYS returned *)
  used : string list;         (* names substituted / paths spliced, sorted *)
  conflicts : string list;    (* one definition: a name defined twice.
                                 Empty for [splice] — a file has no
                                 second definition. *)
  missing : string list;      (* undefined name / unreadable path *)
  cycles : string list;       (* one line per cycle broken *)
  truncated : string list;    (* one line per depth bound reached *)
  anomalies : string list;    (* malformed markers, preserved VERBATIM in
                                 [text] and named here *)
}

(* Default expansion depth, shared by both expanders and REPORTED rather
   than silently applied. *)
val default_depth : int

(* HW.3.10.1 — SUBSTITUTIONS: a definition written once, expanded
   everywhere it is used, at BUILD time.

     definition (a line of its own):  <!-- subst: name = replacement -->
     use (inline, anywhere):          {{name}}

   The definition form is the corpus's existing comment-directive family
   (`<!-- index: ... -->`, HW.2.6.3) — one directive shape, not a second
   one invented for this feature.

   THE LAW: ONE DEFINITION. A name defined twice is a CONFLICT, reported;
   the first definition wins so the document still renders, but the
   corpus says out loud that the author has two answers to one question.
   A definition governs the WHOLE document, not merely the text after it:
   a document is a unit, and making the order of two independent
   paragraphs decide whether a name resolves is exactly the accident this
   feature exists to remove.

   THE DUAL: AN UNDEFINED NAME IS LOUD. It renders as a visible
   `**[undefined substitution: name]**` marker and is reported. It is
   NEVER left as its own literal `{{name}}`: an author reading the output
   must not have to guess whether they are looking at text that expanded
   to itself or at text that did not expand at all.

   TERMINATION. A replacement may itself contain `{{...}}`; expansion
   follows the PATH (not a visited set, so a name used twice in one
   document is legitimate and expands twice) and stops on a name already
   on that path, reporting the cycle. Depth is additionally bounded, and
   the bound is REPORTED — a truncated document that looks complete is
   the failure mode this feature could otherwise introduce.

   MALFORMED IS NOT UNDEFINED. `{{}}`, `{{a b}}`, a definition with no
   `=`, or a directive sharing its line with other text are all preserved
   BYTE FOR BYTE and named in [anomalies]. An unterminated `{{` is
   ordinary prose and passes through untouched, unnamed — a document that
   merely writes two braces is not making a mistake. *)
val definitions : string -> (string * string) list

val substitute : ?depth:int -> string -> outcome

(* HW.3.10.2 — INCLUDE (WHOLE DOCUMENT): splice another document's bytes
   where the directive stands.

     <!-- include: docs/hermes/wiki/preamble.md -->

   THE LAW: THE INCLUDE DENOTES THE FILE. The expansion is the file's
   bytes, unaltered and un-annotated, so drift between an include and its
   source is unrepresentable — `Wiki_transclude`'s argument for notes and
   `Wiki_include`'s for code, made here for whole documents.

   ACYCLIC AND DEPTH-BOUNDED, by the same construction as transclusion:
   [self] seeds the path (so a document including itself is a cycle at
   depth zero), a path member is never re-entered, and the depth bound is
   REPORTED rather than silently applied. Both render a visible marker.

   A MISSING FILE IS LOUD — a marker in the text and a line in [missing].
   A silently empty include is indistinguishable from a file that is
   empty, and the two need opposite fixes.

   PURE: [read] is injected. The default resolver of a caller that has no
   reader must resolve NOTHING, so an include without a reader fails
   closed and says so (the `Wiki_include` discipline).

   It is an INCLUDE OF A DOCUMENT, so it is a LINE directive: the marker
   owns its line. A `<!-- include: ... -->` sharing a line with other
   text is preserved verbatim and named in [anomalies] rather than
   quietly splicing a document into the middle of a sentence. *)
val splice :
  ?depth:int -> read:(string -> string option) -> self:string -> string -> outcome

(* ------------------------------------------------- HW.3.2.3 custom ids

     ## Configuring the gate {#gate-config}

   THE LAW: THE AUTHOR'S ID OVERRIDES THE DERIVED SLUG, AND SURVIVES A
   RETITLE — `anchor o retitle = anchor`. That is the entire point: an
   inbound `[[page#gate-config]]`, from anywhere in the corpus or from
   outside it, must keep working when the heading is reworded. A derived
   anchor makes every heading's text load-bearing; a declared one makes
   the author's promise load-bearing instead.

   THE DUAL: TWO HEADINGS CLAIMING ONE ID IS A COLLISION, REPORTED AND
   NEVER SILENTLY RESOLVED. The derived slugger de-duplicates by
   appending `-1`, `-2`, … and that is right for derived names, which
   nobody promised. It is WRONG for a declared one: renaming the second
   author's `{#setup}` to `setup-1` leaves their declared address
   pointing at someone else's heading, which is worse than a link that
   fails. So both headings keep the id they declared, the document is
   reported as defective, and the author decides. A declared id that
   collides with an already-derived anchor is reported the same way.

   ANCHOR LOCALITY IS PRESERVED (HW.3.2.2). Every function here takes ONE
   BODY and nothing else, so a page's anchors are a function of that page
   alone — a single-page render and a whole-corpus render cannot
   disagree, because there is nothing corpus-shaped to disagree about.

   AGREEMENT WITH THE ENGINE. On a body that declares no custom id, the
   headings here are the engine's headings — same levels, same text, same
   stateful first-wins slugger (`Hermes_wiki.slugify` is reused, not
   re-derived). The feature ADDS an override; it does not fork the anchor
   rules.

   MALFORMED MARKERS ARE PRESERVED VERBATIM. `{#}`, `{#a b}`, or a
   `{#id}` that is not the last token of the heading are left in the
   heading text exactly as written, the anchor derives from that text as
   it does today, and the fault is named in [id_anomalies]. A marker
   inside a fence is an example and is not a heading at all. *)

type heading = {
  hlevel : int;               (* 1..4, as the engine clamps it *)
  htext : string;             (* the heading text with a WELL-FORMED
                                 marker removed — the id addresses the
                                 heading, it is not part of what it says *)
  hanchor : string;
  hcustom : bool;             (* was the anchor declared by the author *)
}

val headings_of : string -> heading list

(* The ids a body emits, in document order. Not deduped: on a collision
   the same id legitimately appears twice, and hiding that here would
   hide the very defect [id_collisions] reports. *)
val anchors_of : string -> string list

(* Declared ids that are claimed twice — one sorted line each. *)
val id_collisions : string -> string list

(* Malformed or misplaced id markers — one sorted line each. *)
val id_anomalies : string -> string list
