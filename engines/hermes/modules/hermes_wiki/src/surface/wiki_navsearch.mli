(* HW.6.4.1 / HW.6.4.3 / HW.6.3.3 / HW.6.3.4 / HW.6.11.1 / HW.6.6.1 —
   the NAVIGATION AND SEARCH surfaces: six register rows that are one
   question asked six ways. Given a corpus and a reader standing
   somewhere in it, what is above them, what is near them, what did they
   ask for, what is still owed, and what did all of that look like at an
   earlier commit.

   THE MODULE ADDS NO SECOND TRUTH. Every answer here is computed from a
   kernel that already exists and is already under law (R14 — reuse or
   mirror, never reinvent):

     tokenisation   Wiki_search.tokens. A code search that tokenised on
                    its own would make two parts of one system disagree
                    about what a word is, and the disagreement would show
                    up as a query that finds a page in prose and loses it
                    in code.
     fences         Wiki_ast.fences — the corpus's ONE fence grammar.
                    Wiki_search excludes fence bodies from the full-text
                    index; HW.6.3.3 indexes exactly their complement, so
                    "prose" and "code" partition the document instead of
                    overlapping by accident.
     ranking        Wiki_graph.pagerank (itself the R14 mirror of zigvm's
                    zk_page_rank_calculator). See HW.6.3.4 below: the
                    personalised ranking IS that function, and the proof
                    is byte equality, not agreement.
     the tree       Wiki_toc — the DECLARED navigation tree. A breadcrumb
                    is a path through it, never a second walk of it.
     the todo mark  Wiki_directive's column-zero `.. name:: argument`
                    grammar and Wiki_callout's `> [!todo]` header, both
                    mirrored rather than imported: the dune stanza that
                    owns this library names neither, and inventing a
                    third spelling of "todo" is the failure this module
                    exists to avoid. The mirror is EXACT — Wiki_callout
                    admits `todo` under one name with no aliases.

   PURE. A function of its arguments alone: no filesystem, no Unix, no
   clock, no randomness, no subprocess. HW.6.6.1 is where that costs
   something, and the cost is paid explicitly — see [history].

   DETERMINISTIC BY LAW, which here is the hardest constraint rather than
   a slogan. [Hermes_wiki.build] preserves the order of the file list it
   was handed, so [model.pages] carries the caller's input order into
   every consumer. Every entry point below therefore sorts before it
   computes, every ranked list carries an explicit total tie-break (score
   descending, then slug ascending), and the one place floats are
   accumulated outside the kernel ([rank_mass]) accumulates in ascending
   slug order. Float addition is not associative: the same masses summed
   in a different order differ in the last bit, and a last-bit difference
   flips a tie and reorders a page. [canonical] exists so a test can
   assert BYTE identity across a shuffled corpus rather than assert that
   two lists look similar.

   TOTAL AT THE EDGES. An empty corpus, a one-page corpus, a graph with
   no edges, a query that matches nothing, a page with no fence, a commit
   nobody recorded: each is a defined value. Nothing here raises, divides
   by zero, or returns NaN. *)

(* ------------------------------------------------------ HW.6.4.1 *)

(* A BREADCRUMB is A RESOLVING PREFIX PATH — two claims, both enforced.

   PREFIX. The crumbs of a page are the crumbs of its parent followed by
   the page itself: [breadcrumb_slugs x = breadcrumb_slugs (parent x) @
   [x]]. Equivalently, and this is the form [test_wiki_navsearch] checks
   over every placed page: for every k, the first k crumbs of x are
   exactly the crumbs of the k-th crumb. A breadcrumb is therefore
   PREFIX-CLOSED, and a reader who clicks the third crumb of a five-crumb
   trail lands on a page whose own trail is those three crumbs. This is
   not enforced by a check; it follows from Wiki_toc's node-once law,
   which makes the path from the root to a slug unique.

   RESOLVING. Every crumb names a page that exists, so every crumb is a
   link that works. A breadcrumb whose middle entry 404s is worse than no
   breadcrumb: it tells a reader there is a section above them and then
   refuses to show it. [breadcrumb_gaps] is the audit that says so out
   loud, and it is expected to be empty by construction — Wiki_toc only
   ever places a slug that resolved through the engine's own key space.
   It is exported anyway, because an invariant nobody can observe is
   indistinguishable from one that has quietly stopped holding.

   TOTAL. A page the declared tree does not place has no declared
   ancestry, so its breadcrumb is the single crumb naming itself — the
   honest answer, and never [] (which would say the page does not exist).
   A slug that names no page at all yields [], which says exactly that. *)
type crumb = {
  slug : string;
  title : string;   (* the page's title; "" when the page is absent *)
  href : string;    (* slug ^ ".html" — the corpus's own URL convention,
                       the one Wiki_ordering.nav_html already emits *)
}

val breadcrumb : Hermes_wiki.model -> Wiki_toc.t -> string -> crumb list
val breadcrumb_slugs : Hermes_wiki.model -> Wiki_toc.t -> string -> string list

(* Crumbs that name no page, one sorted line each. Empty by construction;
   exported so the construction is observable. *)
val breadcrumb_gaps : Hermes_wiki.model -> Wiki_toc.t -> string list

(* ------------------------------------------------------ HW.6.3.3 *)

(* A CODE HIT COMES FROM A FENCE BODY AND FROM NOWHERE ELSE. The negative
   is the whole content of the row: a term that appears only in prose
   yields no code hit, and a term that appears only inside a fence yields
   one. Wiki_search's full-text index excludes fence bodies and this
   index is their complement, so the two searches PARTITION the document:
   a query is never answered twice from the same bytes, and no byte is
   unreachable from both.

   That partition is WITNESSED, NOT PROVEN, and the distinction is worth
   stating. The two sides walk fences differently — Wiki_search uses a
   flat trim-and-toggle over the raw lines, this index uses the block
   carrier — so the partition is a claim about two implementations
   agreeing, which is exactly the kind of claim that rots. It is pinned
   on the shapes where they could most plausibly disagree: a fence inside
   a BLOCKQUOTE (neither side calls it code: the toggle does not fire on
   a `>`-prefixed line and the carrier does not lift it) and an INDENTED
   fence inside a LIST (both sides call it code). If a future change to
   either walk breaks the agreement, that test is where it surfaces.

   The fence walk is Wiki_ast.fences, the corpus's one fence grammar, so
   "what is a fence" cannot drift between the renderer and the search. A
   `toctree` or `doctest` fence indexes as code like any other: the claim
   is "fence bodies only", not "fence bodies whose language I approve of",
   and a special case here would be a second grammar in disguise.

   Tokenisation is Wiki_search.tokens verbatim, so `Foo_bar` is the two
   terms `foo` and `bar` in code exactly as it is in prose.

   A HIT IS A LINE, and that is a stated limit rather than a hidden one:
   a multi-token query matches when all its tokens share one line, so a
   query whose terms straddle a line break finds nothing. Reporting a
   whole fence instead would make the surface unable to point at
   anything, which is the more expensive failure for a search UI.

   Ordering is total: slug ascending, then fence ordinal, then line
   ordinal within the fence. Two identical lines in one fence are two
   hits — they are two places to look. *)
type code_hit = {
  slug : string;
  lang : string;   (* Wiki_ast.lang_of_info of the opener, "" when bare *)
  fence : int;     (* 0-based fence ordinal within the page, source order *)
  line : int;      (* 0-based line ordinal within that fence's body *)
  text : string;   (* the body line, verbatim *)
}

(* ------------------------------------------------------ the index *)

(* One index for the whole surface, carrying the Wiki_search index it is
   defined against. Built once from the model; a function of the corpus
   and nothing else, so [build (shuffle files)] and [build files] are
   byte-identical under [canonical]. *)
type index

val build : Hermes_wiki.model -> index

(* The Wiki_search index this one was built with — exported so a caller
   (and HW.6.4.3's containment test) compares against the SAME index
   rather than a second one built from the same model. *)
val search_index : index -> Wiki_search.index

(* One canonical serialisation of everything the index holds, and its
   in-process identity. As in Wiki_search: an equality witness, NOT an
   evidence pin. *)
val canonical : index -> string
val digest : index -> string

val code_search : index -> string -> code_hit list

(* The pages holding at least one code hit, sorted, deduplicated. *)
val code_slugs : index -> string -> string list

(* ------------------------------------------------------ HW.6.4.3 *)

(* QUICK FIND IS A SUPERSET OF EXACT MATCH. A fuzzy finder that loses an
   exact hit is worse than no finder at all: it teaches a reader that the
   thing they can see with their own eyes is not there. So the law is
   containment, and it is true BY CONSTRUCTION rather than by tuning —
   [quick_find] is a UNION whose first member is [exact_matches], and a
   union only ever grows. In particular there is deliberately NO limit
   parameter: truncation is the one operation that could break the law,
   so a caller who wants ten results takes ten from the head.

   [exact_matches] is what a reader would call "it is right there":
   the slug equals the query, or the title equals the query (compared
   through Hermes_wiki.slugify, so "The Guide" and "the-guide" are one
   thing), or Wiki_search finds the page for that query. The third
   disjunct is the load-bearing one — a page whose body carries the term
   but whose name does not must not fall out of a finder.

   RANKING is by an INTEGER score, so no tie ever depends on a float's
   last bit, with an explicit total tie-break: score descending, then
   slug ascending. The bands do not overlap: an exact slug outranks an
   exact title, which outranks a prefix, which outranks a subsequence,
   which outranks any full-text hit, which outranks a code-only hit. A
   full-text score contributes within its band and can never climb out of
   it, so a page that repeats a word a thousand times cannot displace the
   page that IS that word.

   An EMPTY or all-punctuation query matches nothing. Every slug is
   trivially a supersequence of the empty string, so the alternative is a
   finder that answers "everything" to a question nobody asked. *)
type find_hit = {
  slug : string;
  title : string;
  score : int;
  why : string;   (* the strongest reason this page matched, named *)
}

val exact_matches : index -> string -> string list
val quick_find : index -> string -> find_hit list

(* ------------------------------------------------------ HW.6.3.4 *)

(* ONE KERNEL, TWO CONSUMERS. The global ranking and the personalised
   ranking are the SAME function — Wiki_graph.pagerank, the R14 mirror of
   zigvm's zk_page_rank_calculator — called with two teleport vectors.
   There is no second power iteration in this module and there must never
   be one: two implementations that agree today diverge within a month,
   and the divergence is invisible because both answers look plausible.

   THE PROOF IS BYTE EQUALITY, NOT AGREEMENT:

     rank_canonical (rank_personal ~seeds:(Wiki_graph.nodes g) g)
       = rank_canonical (rank_global g)

   Seeding every node distributes the teleport mass uniformly, which is
   what an unseeded rank does by definition, so the two runs must produce
   the same floats to the last bit — [rank_canonical] prints them in hex
   (%h) precisely so "the same" means the same and not "the same to six
   places". The same holds for [rank ~seeds:[]]. A test that compared
   rounded floats would pass against a second implementation; this one
   cannot.

   AN UNKNOWN SEED LEAVES A MARK. Wiki_graph.pagerank silently ignores a
   seed naming no node, and a personalised rank whose seeds are ALL
   unknown silently degrades into the global rank — the caller asked
   "what is near this page" and got "what is important in general",
   which is a plausible-looking wrong answer. [ranking] therefore carries
   [seeds_unknown], sorted; the degradation is still allowed, but it is
   never silent.

   TOTAL: an empty graph ranks to [], never a division by zero. A
   disconnected graph ranks every component, because the teleport reaches
   every node. *)
type ranking = {
  rows : (string * float) list;   (* every node: score desc, ties slug asc *)
  seeds_used : string list;       (* the seeds that named a node, sorted *)
  seeds_unknown : string list;    (* the seeds that named nothing, sorted *)
}

(* THE one entry point. [seeds = []] is the uniform teleport. *)
val rank : ?seeds:string list -> Wiki_graph.g -> ranking

(* The two consumers, both defined over [rank] and holding no arithmetic
   of their own. *)
val rank_global : Wiki_graph.g -> ranking
val rank_personal : seeds:string list -> Wiki_graph.g -> ranking

(* Consumer two's actual surface: what is near THIS page. The seed page
   is dropped from the rows — a page is not its own neighbour, and
   leaving it in would put it first every time and say nothing. An
   unknown page yields empty rows and names itself in [seeds_unknown]. *)
val related : Wiki_graph.g -> string -> ranking

(* Hex-float (%h) serialisation — byte-exact, so equality of two
   canonical strings is equality of the underlying doubles. *)
val rank_canonical : ranking -> string

(* The total rank mass of a set of slugs. THE one float accumulation
   outside the kernel, and therefore the one place an order-dependent sum
   could hide: it folds over the slugs sorted ascending and deduplicated,
   so the result is a function of the SET and not of the list. Slugs the
   ranking does not name contribute 0.0. *)
val rank_mass : ranking -> string list -> float

(* ------------------------------------------------------ HW.6.11.1 *)

(* COMPLETE; EVERY MARKED TODO ONCE.

   COMPLETE means every mark the dialect defines is collected, and the
   dialect defines exactly two — the Sphinx directive `.. todo::` at
   column zero (Wiki_directive's grammar) and the Obsidian callout
   `> [!todo]` (Wiki_callout's, which admits that one spelling and no
   aliases). Both are mirrored here rather than imported, because the
   dune stanza that owns this library depends on neither; the mirror is
   named so a later consolidation is mechanical. Collecting only one of
   the two forms would make "complete" false for half the corpus.

   ONCE means each mark yields exactly one entry, keyed by (slug, line).
   Two todos with identical text on different lines are two todos — they
   are two pieces of work. The same todo is never counted twice, because
   a line is scanned once.

   CODE IS NOT PROSE, and a bare word is not a mark. A `.. todo::` inside
   a fence describes the grammar and is not a use; a marker indented, or
   preceded by a backtick, is not at column zero and is not a use; and
   `TODO: fix this` written in a sentence is a sentence. Widening the
   grammar to catch it would make the count depend on how people write
   rather than on what they declared.

   Sorted by (slug, line) — a total order, since a line is scanned once
   per page. *)
type todo_form =
  | Directive   (* `.. todo:: argument`, body indented *)
  | Callout     (* `> [!todo] title` *)

type todo = {
  slug : string;
  line : int;             (* 0-based line index within the page's raw body *)
  form : todo_form;
  text : string;          (* the argument / title, trimmed; "" when absent *)
  body : string list;     (* de-indented continuation lines, verbatim *)
}

val todos : Hermes_wiki.model -> todo list

(* The todos of one page, in line order — the per-page surface, defined
   over [todos] so a page view and the corpus collection cannot disagree
   about what is owed. *)
val todos_of : Hermes_wiki.model -> string -> todo list

(* ------------------------------------------------------ HW.6.6.1 *)

(* as_of(c) = build(checkout c), AS AN IDENTITY RATHER THAN AS A GOAL.

   THE INJECTION DECISION, stated because it is the whole design: the
   corpus-at-a-commit arrives as DATA — a (path, content) list per
   revision, handed to [history_of] by the caller — and this module never
   shells out to git, never reads the filesystem, and never asks what
   time it is. The reason is not tidiness. A module that ran `git
   checkout` would be untestable without a repository, unable to answer
   about a commit that is not checked out, and would make an as-of query
   depend on the state of a working tree that another process can change
   underneath it. Reading a revision is the caller's business and belongs
   at the IO edge, exactly where Hermes_wiki.read_tracked already lives.

   Given that, the law is not something to verify but something to read:
   [as_of h c] is literally [Option.map Hermes_wiki.build (checkout h c)].
   The model is RE-DERIVED from the revision's bytes on every call rather
   than cached, so an as-of answer cannot be a stale answer.

   ORDER IS DECLARED, NOT INFERRED. Each revision carries an explicit
   [order], so [history_of] is insensitive to the order of the list it is
   given: a shuffled revision list is the same history. Commit identity
   is the key; a repeated commit id keeps the entry first in (order,
   commit) sequence and is REPORTED by [duplicate_commits], never merged
   and never silently overwritten.

   TOTAL: an unknown commit is [None] — distinct from [Some []], which is
   a real revision that happens to contain no files. A tool that cannot
   tell those apart will re-pin an artifact to nothing and exit 0. *)
type revision = {
  commit : string;                  (* the revision's identity *)
  order : int;                      (* position in commit order, declared *)
  files : (string * string) list;   (* the corpus at that revision *)
}

type history

val history_of : revision list -> history

(* Commit ids in commit order: [order] ascending, ties by commit id. *)
val commits : history -> string list

(* Commit ids declared more than once, sorted — loud, never merged. *)
val duplicate_commits : history -> string list

(* The corpus at a commit, sorted by path so the snapshot is canonical.
   [None] when the commit is unknown; [Some []] when it is empty. *)
val checkout : history -> string -> (string * string) list option

(* The model at a commit. By definition [Option.map Hermes_wiki.build
   (checkout h c)] — the identity above, spelled out in the source. *)
val as_of : history -> string -> Hermes_wiki.model option

(* The navsearch index at a commit — the surface an as-of query actually
   wants. Defined over [as_of], so it cannot see a different corpus than
   the model does. *)
val index_as_of : history -> string -> index option
