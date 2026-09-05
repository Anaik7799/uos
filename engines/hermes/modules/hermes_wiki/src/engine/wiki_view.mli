(* HW.5.3.1–6 — the query VIEW family: six ways of LOOKING at one query
   result, and no way of disagreeing about what the result was.

   THE SHAPE OF THE FAMILY IS THE SPECIFICATION. Read the six claims
   together and one law falls out of them:

     HW.5.3.1 Table view          "rows derived, never stored"
     HW.5.3.2 Board (kanban)      "a rendering of one result"
     HW.5.3.3 Kanban (Obsidian)   "query-defined, not file-defined"
     HW.5.3.4 Gallery view        "card grid over one result"
     HW.5.3.5 List view           "compact rendering"
     HW.5.3.6 Charts              "deterministic inline SVG"

   FIVE OF THE SIX ARE RENDERINGS OF ONE RESULT SET. So the load-bearing
   law of this whole module is a SET EQUALITY, not a rendering detail:

     THE SET LAW — for every result [t], the five renderers in [renderers]
     emit exactly the same row identifiers in exactly the same order, and
     that common sequence carries exactly the rows [Wiki_query.eval]
     returned: it IS eval's sequence when [t] is ungrouped, and a
     permutation of it (eval's rows, regrouped) when [t] is grouped,
     because a bucket ordering may reorder rows but a partition may not
     add or lose one.

   Both directions matter and the module is arranged so that neither can
   be quietly lost:

     - No view may show a row the query did not return. A board column
       that invents a card is a claim about the corpus that the corpus
       does not make.
     - No view may hide a row the query did return. This is the failure
       that looks harmless: a gallery that silently drops the last card
       reads as "there were only nine", and nothing on the page says
       otherwise. A reader comparing the table and the board would see two
       different corpora and have no way to tell which one is real.

   The law is CHECKABLE, not merely asserted, because every renderer marks
   every row it emits with `data-row="<slug>"` and [row_ids] reads those
   marks back out of the finished markup. The test therefore observes what
   the views ACTUALLY EMITTED rather than what they were meant to emit —
   the only form of this law that can fail.

   WHY THE RESULT TYPE IS NOT A NEW ROW TYPE. [t] carries
   [Wiki_query.group]'s output verbatim: `Hermes_wiki.page list` per
   bucket. A parallel "view row" record would be a second place where a
   field can be stale, and HW.5.3.1's claim — "rows derived, never
   stored" — is precisely the refusal to have one. Every cell in every
   view is a projection of the page computed at render time.

   R14 (reuse or mirror, never reinvent). Two mirrors, both structure
   preserving:
     - the table, its column set, the `zq-*` class vocabulary and the
       "%d row%s" count footer mirror `render_zkquery_results_elts` in
       the imported zigvm `docs_wiki.ml` (~§2430), which is the same
       feature emitting typed elements instead of strings;
     - the chart mirrors `bar_chart` in `modules/hermes_harness/
       site_build.ml`: horizontal bars, label gutter, integer geometry.

   PURITY. Model in, string out. No filesystem, no clock, no randomness,
   no mutable global. A view is a function of [t] alone, which is what
   makes a rendered page pinnable by a byte baseline.

   DETERMINISM BY CONSTRUCTION, not by convention. Bucket order is
   [Wiki_query.group]'s order (sorted keys); row order within a bucket is
   [Wiki_query.eval]'s total order (the slug tiebreak). Nothing here folds
   a hash table, so no output depends on an iteration order that is free
   to change between runs. HW.5.3.6's "deterministic inline SVG" is
   enforced the blunt way: EVERY SVG COORDINATE IS AN INTEGER, computed by
   integer arithmetic. No float is formatted anywhere in this module, so
   there is no precision or locale drift to pin against.

   TOTAL AT THE EDGES. An empty result renders an EMPTY VIEW: the frame,
   the column headers, `data-rows="0"` and the `zq-empty` class — never a
   crash, and never a placeholder row that a reader could mistake for
   data. A bucket with no rows is still rendered, because a silently
   omitted bucket is a claim that the category does not exist.

   ESCAPING IS PART OF THE SET LAW, NOT DECORATION. All author text —
   titles, tags, group names, bucket keys, the query source — goes through
   [escape_html] into both HTML and SVG. Two consequences, and the second
   is the one people forget: an unescaped `<` is an injection, AND a title
   containing `" data-row="ghost` would otherwise FORGE a row identifier,
   making a view report a row that no query returned. Escaping is what
   makes [row_ids] an honest observation of the result. *)

(* A rendered query result: the buckets exactly as [Wiki_query.group]
   returned them, plus the two facts a renderer needs and cannot recover
   from the bucket list alone.

   [grouped] distinguishes the two results that both look like a single
   `""`-keyed bucket: a query with no `group by` (one anonymous bucket,
   labelled [unbucketed_label]) and a `group by` whose key is ABSENT on
   every row (a real bucket, labelled [absent_key_label]). Conflating them
   would label a whole corpus "(none)".

   [source] is the query text, which HW.5.3.3 needs: a kanban board here
   is DEFINED BY THE QUERY, so it carries the query, not a file path.

   The fields are public on purpose. A test or a probe must be able to
   build the results a corpus cannot produce — a duplicate row identifier,
   an absent bucket key beside a named one — and an abstract type would
   make exactly the edge cases this module must survive unrepresentable in
   the tests that prove it does. *)
type t = {
  source : string;                                  (* the query text *)
  grouped : bool;                                   (* a `group by` clause was present *)
  buckets : (string * Hermes_wiki.page list) list;  (* Wiki_query.group's output *)
}

(* [of_query ~source pages q] evaluates and buckets in one step. It is the
   ONLY constructor that talks to the query engine, so a view can never
   see rows that [Wiki_query.eval] did not produce. *)
val of_query : source:string -> Hermes_wiki.page list -> Wiki_query.query -> t

(* Parse then evaluate. TOTAL: a malformed query is the parser's NAMED
   error, propagated verbatim — never an empty view, which would be
   indistinguishable from a query that matched nothing. *)
val of_source : Hermes_wiki.page list -> string -> (t, string) result

(* The rows of every bucket, in emission order. For a [t] built by
   [of_query] this is exactly [Wiki_query.eval pages q] — reordered by the
   buckets when a `group by` is present, never added to or thinned. That
   identity is the anchor the set law is checked against. *)
val rows : t -> Hermes_wiki.page list
val row_count : t -> int

(* The two names that keep an absent value VISIBLE. A bucket, or a derived
   field, that is empty is rendered under a name; it is never dropped and
   never left as a blank a reader would read as "not applicable". *)
val unbucketed_label : string   (* the single bucket of an ungrouped result *)
val absent_key_label : string   (* a grouping key, or a field, that is absent *)

(* The label a bucket key is rendered under, per the rule above. *)
val bucket_label : t -> string -> string

(* HW.5.3.1 — the table's columns, in order. Every one is DERIVED from the
   page at render time; none is stored. The table emits exactly
   [List.length columns] header cells and exactly that many cells per row,
   so a column added without a projection is a shape error, not a silently
   ragged table. *)
val columns : string list

(* The six views. Each takes the same [t] and returns an HTML (or SVG)
   FRAGMENT — no document, no <style>, no script, no external reference. *)
val table : t -> string        (* HW.5.3.1 *)
val board : t -> string        (* HW.5.3.2 *)
val kanban : t -> string       (* HW.5.3.3 *)
val gallery : t -> string      (* HW.5.3.4 *)
val list_view : t -> string    (* HW.5.3.5 *)
val chart : t -> string        (* HW.5.3.6 *)

(* THE SCOPE OF THE SET LAW, as data. These five renderings differ only in
   presentation, so they must agree on the rows exactly; [chart] is
   deliberately absent because it is an AGGREGATE, and its own covering
   law is [chart_counts] below. A sixth rendering of the result set joins
   this list, and by joining it comes under the law. *)
val renderers : (string * (t -> string)) list

(* The row identifiers a rendered view ACTUALLY emitted, in emission
   order — every `data-row="…"` in the markup. Reading the finished bytes
   is the point: it observes the view rather than trusting it, so a
   renderer that drops or invents a row is caught by the same function for
   every view.

   Identifiers are returned in their ESCAPED attribute form. Every view
   escapes identically, so the law compares like with like; and because
   author text is escaped too, no title can inject an identifier here.

   The scanner matches `data-row` followed by an equals sign and a quote,
   which the root element's `data-rows` attribute cannot satisfy — the
   byte after `data-row` there is `s`, not a quote. *)
val row_ids : string -> string list

(* HW.5.3.6 — what the chart charts: (bucket label, row count) in bucket
   order. THE COVERING LAW: the counts sum to [row_count], so a chart can
   neither lose a row into an unplotted bucket nor double-count one. This
   is the aggregate analogue of the set law, and it is what makes the
   chart checkable without reading its geometry. *)
val chart_counts : t -> (string * int) list

(* HW.5.3.5 — "compact rendering" stated as an inequality that can fail,
   and stated MARGINALLY, which is what the word means: one more row costs
   strictly fewer bytes in [list_view] than in [table] or [gallery]. The
   marginal form is the honest one — a whole-document comparison is
   dominated by the table's header and footer, so a list that quietly
   grew per-row cells would still measure smaller and the claim would go
   unchecked. The list is the SAME set, said in fewer bytes per row. *)
