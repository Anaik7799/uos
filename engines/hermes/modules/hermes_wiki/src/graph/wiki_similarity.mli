(* HW.4.3.2 / HW.4.1.7 / HW.4.2.4 / HW.4.5.2 / HW.4.6.2 / HW.4.6.3 — the
   remaining graph-analysis kernels, in one module because they are one
   question asked six ways: given a corpus, what SHAPE does it have —
   which notes read alike, which tags contain which, who brokers between
   clusters, what sits near a note, what a cluster's landmark is, and how
   a partition adds up.

   Every function here is a MONITOR (R5). It senses and reports a shape
   of the corpus; nothing it returns is a defect of an implementation, so
   nothing it returns may ever deny parity credit. "This note has no
   neighbours" is a fact about a corpus, not a bug in code.

   PURE: model in, values out. No filesystem, no clock, no randomness, no
   Unix. The only inputs are [Hermes_wiki.model] and plain strings.

   DETERMINISTIC BY LAW, which is the whole difficulty of this module.
   [Hashtbl.fold] visits in an order that depends on insertion history,
   so no result is ever emitted from a fold: every list is sorted before
   it leaves, and every ranked list carries an explicit TOTAL tie-break
   (score descending, then slug ascending). A ranking without a total
   tie-break is a ranking that changes when the input list is shuffled,
   and every downstream pin built on it is noise rather than evidence.

   FLOATING POINT, decided deliberately. Cosine similarity accumulates
   sums of products, and float addition is not associative: the same
   terms summed in a different order differ in the last bit, which flips
   a tie and reorders the output. Three constructions remove that:

     1. CANONICAL ORDER. Documents are ordered by slug and terms by term,
        everywhere, so the SEQUENCE of float operations is a function of
        the corpus alone and not of the input list's order. Bit-identity
        under shuffling is therefore structural, not lucky.
     2. CLAMP then QUANTIZE. The raw cosine is clamped into [0, 1] — an
        accumulated sum can exceed 1 by an ulp, and a similarity above
        "identical" is meaningless — and then rounded to the fixed grid
        [quantum] (1e-6). A last-bit difference cannot survive rounding
        to the sixth decimal, so it can never reorder two documents.
     3. COMMUTATIVITY, used where it is exact. IEEE multiplication IS
        commutative, so dot(a,b) and dot(b,a) multiply the same pairs and
        sum them in the same term order: symmetry is bit-exact, not
        approximate. [similarity v a b = similarity v b a] holds with
        [=], for every pair, always.

   The determinism claim is scoped honestly: SAME CORPUS, SAME BINARY
   gives byte-identical output. [log] is libm, so a different libm could
   in principle move a weight; the quantized score would still have to
   move a full 1e-6 to reorder anything, and [canonical] makes any such
   drift visible rather than silent.

   TOTAL AT THE EDGES. An empty corpus, a single page, a page with no
   tokens, a term in every document, an absent slug, a negative radius
   and a fully disconnected graph each return a DEFINED value. Nothing
   here raises, nothing returns NaN, nothing divides by zero. *)

(* ------------------------------------------------------------------ *)
(* HW.4.3.2 — TF-IDF cosine similarity                                 *)
(* ------------------------------------------------------------------ *)

(* Tokenisation is an R14 MIRROR of [Wiki_search.tokens], byte for byte:
   lowercase, maximal runs of ASCII [a-z0-9], runs shorter than two
   characters discarded. It is copied rather than called because the
   similarity library may not depend on the search library, and the
   duplication is the lesser evil: if similarity and search disagreed
   about what a word is, a note could be "related" to a note no query
   can ever retrieve alongside it, and no test would notice. Any change
   to one must be made to the other; [tokens] is exposed precisely so a
   test can pin the two against each other by value. *)
val tokens : string -> string list

(* The text a document contributes, in order: the fence-excluded body
   lines of the raw note, each with its trailing `^block-anchor` removed.
   Fences are excluded because a code sample is not prose about the note
   — the row's stated convention, and the same one the search index
   uses. Anchors are removed because `^a1b2` is an ADDRESS, not a word;
   counting it as a term would make two notes similar for having been
   annotated rather than for saying the same thing. *)
val document_text : Hermes_wiki.page -> string list

(* The corpus TF-IDF model. Abstract: it holds one canonical, sorted
   weight vector per page plus the document frequencies, so every
   consumer sums in the same order. *)
type vectors

(* Built from the model. Pages are ordered by slug and terms by term
   BEFORE any arithmetic happens, so [vectors] is a function of the set
   of pages and never of the order they arrived in. *)
val vectors : Hermes_wiki.model -> vectors

(* N — the number of documents. An empty corpus has size 0 and every
   other function degrades to its empty value rather than dividing. *)
val corpus_size : vectors -> int

(* n_t — how many documents contain the term. 0 for a term nobody wrote. *)
val document_frequency : vectors -> string -> int

(* idf(t) = 1 + ln(N / n_t), exactly as the row claims. The +1 is
   load-bearing and not decoration: without it a term appearing in EVERY
   document has idf 0, which annihilates that coordinate and — in a
   corpus where every note shares its whole vocabulary — makes every
   vector zero and every cosine a 0/0 NaN. With it, a universal term
   scores exactly 1.0 and the measure stays defined.

   Total: idf of an unknown term (n_t = 0) is 0.0, and idf over an empty
   corpus is 0.0. A term nobody wrote carries no weight; it is not an
   error to ask about one. *)
val idf : vectors -> string -> float

(* The weight vector of a page: sorted (term, tf * idf) pairs, tf being
   the RAW occurrence count. The search index's 3x heading boost is
   deliberately NOT mirrored here: that boost is a query-ranking
   heuristic about where a reader's word appears, whereas this is a model
   of what a document IS. The two share their tokenizer, not their
   weights. [] for a page not in the corpus. *)
val weights : vectors -> string -> (string * float) list

(* The grid every score is rounded to (1e-6). Exposed so a test can state
   the resolution rather than guess it. *)
val quantum : float

(* Cosine similarity of two pages, clamped to [0, 1] and quantized to
   [quantum]. Laws, each of which a test names and proves:

     SYMMETRY   similarity v a b = similarity v b a, with [=], for every
                pair including absent ones. Exact, by the commutativity
                of IEEE multiplication over a shared sorted term order.
     IDENTITY   similarity v a a = 1.0 for every page a IN the corpus.
                This is DEFINED, not computed: sqrt(x) *. sqrt(x) is not
                x in binary floating point, and a note with no tokens at
                all has a zero vector whose self-cosine is 0/0. A
                document is maximally similar to itself by the meaning of
                the measure, so the reflexive case is answered by the
                measure's definition rather than by its arithmetic.
     RANGE      0.0 <= similarity v a b <= 1.0, always.
     ABSENCE    0.0 when either slug is not a page. Asking about a note
                that does not exist is answered, not raised.
     EMPTINESS  0.0 when either vector is zero and the slugs differ — a
                note with no words is not similar to anything, and is
                certainly not NaN-similar to it. *)
val similarity : vectors -> string -> string -> float

(* The related notes of a page: every OTHER page with a non-zero
   similarity, score descending, ties slug ascending — a total order, so
   the list is a function of the corpus. [?limit] truncates the ranked
   list (a limit <= 0 returns []; an absent limit returns all of them).
   [] for a slug that is not a page. *)
val related : ?limit:int -> vectors -> string -> (string * float) list

(* One canonical line per document frequency and per weight, weights
   printed at %.17g so no rounding hides a difference. This is the
   determinism receipt: the same corpus built from a SHUFFLED input list
   must produce a byte-identical string. Not an evidence pin — a pinned
   model goes through the sha256 oracle like every other baseline. *)
val canonical : vectors -> string

(* ------------------------------------------------------------------ *)
(* HW.4.1.7 — nested tags                                              *)
(* ------------------------------------------------------------------ *)

(* A tag is a '/'-separated PATH, and the path is the whole point: `#a/b`
   is a kind of `#a`, so a reader who asks for `#a` must be given it.

   The tag universe of a page is its body `#tags` together with its
   frontmatter `topics`, normalised. Both, because the body scanner
   (`Hermes_wiki.tags_of_line`) stops at '/' — a body `#a/b` yields the
   tag `a` — so a nested path can only reach the model through
   frontmatter. Reading only one of the two sources would make half the
   corpus's tags invisible to the very order this row is about. *)

(* Normalisation, total: lowercase, one leading '#' removed, empty
   segments dropped ("#A//B/" -> "a/b"). "" and "#" and "///" normalise
   to "", which belongs to no page and covers nothing. *)
val tag_normalise : string -> string

(* The segments of a normalised tag: "a/b/c" -> ["a"; "b"; "c"]. *)
val tag_segments : string -> string list

(* Every ancestor of a tag, itself included, shortest first:
   "a/b/c" -> ["a"; "a/b"; "a/b/c"]. [] for the empty tag. *)
val tag_ancestors : string -> string list

(* [tag_covers ~parent ~child]: does the child tag imply the parent?
   SEGMENT-WISE prefix, never string prefix — this is the distinction the
   row exists to make. Laws, each proved by a named test:

     REFLEXIVE   tag_covers ~parent:t ~child:t
     TRANSITIVE  covers a b && covers b c  =>  covers a c
     NOT-STRING  `#a` does NOT cover `#ab`. A string-prefix test would
                 file `#abstract` under `#a`, which is not a hierarchy,
                 it is a coincidence of spelling.
     EMPTY       the empty tag covers nothing and is covered by nothing,
                 so a malformed tag cannot become a root that swallows
                 the corpus. *)
val tag_covers : parent:string -> child:string -> bool

(* The normalised tags a page declares, sorted and deduplicated. Note
   these are the DECLARED tags only — [tag_members] is where the implied
   ancestors are honoured. *)
val page_tags : Hermes_wiki.page -> string list

(* The pages under a tag: every page carrying that tag OR any descendant
   of it, sorted. This is the row's claim — "prefix order is monotone in
   members" — stated as a law a test can break:

     MONOTONE   tag_covers ~parent:a ~child:b  =>
                tag_members m b  is a subset of  tag_members m a

   so filtering by `#a` returns everything tagged `#a/b`, and narrowing a
   filter can only ever remove pages. [] for the empty tag. *)
val tag_members : Hermes_wiki.model -> string -> string list

(* Every tag in the corpus INCLUDING the ancestors implied by its
   children, each with its members. Sorted by tag; members sorted. A
   corpus containing only `#a/b` therefore lists both `a` and `a/b`: an
   implied ancestor is a real tag, or the hierarchy has holes in it. *)
val tag_tree : Hermes_wiki.model -> (string * string list) list

(* ------------------------------------------------------------------ *)
(* The shared neighbourhood relation                                   *)
(* ------------------------------------------------------------------ *)

(* The three graph rows below need adjacency, and [Wiki_graph.g] is
   abstract with no accessor for it. Rather than declare a second graph
   type — which could disagree with the one the rest of the system ranks
   and clusters on — the node set is taken from [Wiki_graph.nodes]
   verbatim and adjacency is DERIVED from the model by mirroring
   [Wiki_graph.of_model]'s resolution rule exactly: an outlink counts
   only when its target is itself a page, self-loops are dropped, and
   duplicates collapse. The mirror is not asserted, it is CHECKED: a test
   pins [List.length (directed_edges m)] against
   [Wiki_graph.edge_count (Wiki_graph.of_model m)], so the day the two
   resolution rules diverge, the suite says so rather than the two halves
   of the system quietly analysing different graphs.

   The relation is UNDIRECTED — the same neighbourhood [Wiki_graph.
   communities] propagates labels over. A backlink is as much a
   neighbour as a link; a reader who follows a citation backwards has
   travelled one hop. *)

(* The resolved link edges as [Wiki_graph] sees them — one per (source,
   distinct resolved target), sorted. Exposed for the mirror check above
   and for nothing else; the analyses below all read the undirected view. *)
val directed_edges : Hermes_wiki.model -> (string * string) list

(* Undirected edges of the corpus, each as (u, v) with u < v, sorted. *)
val edges : Hermes_wiki.model -> (string * string) list

(* Undirected degree of every page, sorted by slug. Every page appears,
   including the isolated ones at 0 — a gauge that omits its zeros
   cannot tell an isolated note from a note it forgot to look at. *)
val degrees : Hermes_wiki.model -> (string * int) list

(* Undirected BFS distance from a slug to every REACHABLE page, itself
   included at 0, sorted by slug. Unreachable pages are absent rather
   than present at infinity. [] for a slug that is not a page. *)
val hops : Hermes_wiki.model -> string -> (string * int) list

(* ------------------------------------------------------------------ *)
(* HW.4.5.2 — local graph (neighbourhood)                              *)
(* ------------------------------------------------------------------ *)

type neighbourhood = {
  center : string;
  nodes : string list;                 (* sorted, centre included *)
  edges : (string * string) list;      (* induced, (u, v) with u < v, sorted *)
}

(* The radius-limited neighbourhood of a note. It is a SUBGRAPH, and
   subgraph means both directions of one law — a test proves each
   separately, because either alone is satisfiable by a wrong answer:

     SOUND      every node in it is within r hops of the centre
                (a neighbourhood that includes a stranger is not local)
     COMPLETE   every node within r hops of the centre is in it
                (a neighbourhood that omits a neighbour is not a
                 neighbourhood; it is a sample)
     ZERO       radius 0 is the note alone, with no edges
     INDUCED    its edges are exactly the corpus edges whose BOTH
                endpoints are in [nodes] — an edge to somewhere outside
                the view would draw a line to nothing
     MONOTONE   nodes at radius r are a subset of nodes at radius r+1

   Total: a negative radius is read as 0 rather than refused, and an
   absent slug yields an EMPTY neighbourhood (no nodes, no edges) — a
   view of a note that does not exist shows nothing, and shows it
   without raising. *)
val local_graph : Hermes_wiki.model -> radius:int -> string -> neighbourhood

(* ------------------------------------------------------------------ *)
(* HW.4.2.4 — structural holes                                         *)
(* ------------------------------------------------------------------ *)

(* Burt's brokerage, read off the communities the system ALREADY has.
   The span of a page is the number of DISTINCT communities, other than
   its own, among its undirected neighbours: a page spanning two or more
   sits across a structural hole, and a reader arriving there can reach
   parts of the corpus that do not otherwise meet.

   Grounded in [Wiki_graph.communities], never in a fresh clustering.
   A second clustering would eventually disagree with the first, and
   then "this note brokers between clusters" would be a claim about a
   partition nothing else in the system uses.

   REPORT-ONLY (R5), and the row says so: it never mutates the graph and
   never could — it takes a model and returns a list. A high span is not
   a defect and a zero span is not a failure; both are shapes.

   Every page appears, span descending, ties slug ascending. Totality by
   coverage: the result has exactly one entry per page, so an empty
   corpus gives [] and a disconnected corpus gives every page at 0. *)
val structural_holes : Hermes_wiki.model -> (string * int) list

(* ------------------------------------------------------------------ *)
(* HW.4.6.2 — community-grounded MoCs                                  *)
(* ------------------------------------------------------------------ *)

(* One Map of Content per community: the community's most connected
   member is its landmark. The row's claim, stated as laws:

     GROUNDED   the communities are exactly [Wiki_graph.communities] —
                same partition, same membership, verbatim. A MoC that
                named a cluster nobody else recognises would send a
                reader somewhere the rest of the system cannot follow.
     TOP-DEGREE the hub is the member of greatest undirected degree,
                ties by slug ascending
     DEGREE>0   a community whose hub has degree 0 yields NO MoC. A
                landmark nothing links to is not a landmark.
     UNLINKED   a corpus with no links therefore yields [], not one MoC
                per page — which is the degenerate answer that would
                make the gauge useless exactly when it matters.
     COVER      every member of every emitted community appears, so a
                MoC never silently omits part of its own cluster.

   Sorted by hub slug; members sorted. *)
val community_mocs : Hermes_wiki.model -> (string * string list) list

(* ------------------------------------------------------------------ *)
(* HW.4.6.3 — rollup / aggregation                                     *)
(* ------------------------------------------------------------------ *)

(* Aggregation over a partition of the corpus. [key] assigns each page to
   a bucket and [value] scores it; the bucket totals are returned sorted
   by key. The row claims a COMMUTATIVE MONOID, and (int, +, 0) is one,
   so the laws are the monoid's own:

     ORDER-INDEPENDENT  rollup of a shuffled corpus equals rollup of the
                        corpus. Addition commutes and the keys are sorted
                        on the way out, so input order cannot be read
                        back off the result.
     IDENTITY           a bucket with no pages does not exist, rather
                        than existing with a fabricated 0 — the monoid's
                        identity is not evidence of a bucket.
     COVER              the parts sum to the whole:
                        sum of values = sum over all pages of value(p).
                        This is the law that matters most and the easiest
                        to lose: a page whose key is "" belongs to the ""
                        bucket and is COUNTED. Dropping it — the obvious
                        "skip the blank ones" — silently answers a
                        different question than the one asked, and
                        answers it with a number that still looks right.

   Total: an empty corpus rolls up to []. *)
val rollup :
  Hermes_wiki.model ->
  key:(Hermes_wiki.page -> string) ->
  value:(Hermes_wiki.page -> int) ->
  (string * int) list

(* [rollup] with value 1 — bucket sizes. Its cover law is the plain one:
   the counts sum to the number of pages in the corpus. *)
val rollup_count : Hermes_wiki.model -> key:(Hermes_wiki.page -> string) -> (string * int) list

(* Pages per community, keyed by the community's smallest member slug —
   the same key [Wiki_graph.communities] uses, so a rollup row and a
   community row name the same thing. Covers: the counts sum to the
   number of pages, because the communities partition the corpus. *)
val rollup_communities : Hermes_wiki.model -> (string * int) list
