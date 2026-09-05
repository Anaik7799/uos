---
id: hermes-unified-functional-atlas
status: published
type: decision
ktype: moc
maturity: incubating
domain: formal_verification
topics: [atlas, typed-surface, structures, modules]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Unified functional atlas — every capability as a typed function with its structure

#feature #src-unified #area-atlas #cov-design

Maximal coverage on two axes at once:

- **entity coverage** — every entity and relation in `[[Unified domain ontology]]`
  has an OCaml value with a signature (§9 is the completeness check);
- **structure coverage** — every capability is placed on a named functional
  structure: functor, applicative, monad, comonad, traversal, optic, recursion
  scheme, fixed point, monoid, lattice, or Galois connection (§0 is the index).

A structure is claimed only where its laws genuinely hold and buy something.
Where the obvious structure is *rejected*, that is recorded — a rejected
structure is information (§10).

## 0. The structure index

| # | Structure | Where it is used | What it buys |
|---|---|---|---|
| S1 | **Polynomial functor + initial algebra** `μX. F X` | `Ast.t` | `render` is the *unique* algebra morphism ⟹ compositional by theorem |
| S2 | **Catamorphism** | `Render.to_`, `Ast.anchors`, `Ast.depth` | fold with no explicit recursion; a new target = a new algebra |
| S3 | **Anamorphism** | line stream from source | unfold; termination from the seed shrinking |
| S4 | **Hylomorphism** | `Ast.parse = cata alg ∘ ana coalg` | no intermediate list is materialised |
| S5 | **Paramorphism** | `Transclude.expand` | the step sees the *original* subtree, needed for cycle detection |
| S6 | **Traversable** | `Ast.traverse` | one rewrite skeleton for every AST pass, in any applicative |
| S7 | **Validation applicative** | `Meta.parse`, `Corpus.load` | **accumulates** every diagnostic; a document with three faults reports three |
| S8 | **Result monad** | `Query.parse`, gates | **short-circuits**; the first refusal is the answer |
| S9 | **Reader monad** | `Render` (resolve), `Query.eval` (corpus) | ambient context without a global |
| S10 | **State monad** | `Slugger` | duplicate anchors get deterministic suffixes; locality = one run per doc |
| S11 | **Writer monoid** | `Diagnostic.t list` | free monoid: collection is associative, order-independent per pass |
| S12 | **Store comonad** | `Corpus.focused` | corpus-wide derived views computed for **every** page at once |
| S13 | **Lens** | `Meta` fields | get/put/put-put; a field update is law-checked |
| S14 | **Prism** | `Ast.block` constructors | partial focus on one constructor; the basis of typed rewrites |
| S15 | **Traversal (optic)** | "every fence", "every heading" | one combinator per query-over-AST |
| S16 | **Zipper — `∂(Ast)`** | block-anchor patching | one-hole context: patch **one block** without rebuilding the document |
| S17 | **Partial-map monoid** | `Resolver`, `Inventory.consume` | left-biased union, associative, unit = empty ⟹ resolution order is a *stated policy* |
| S18 | **Join-semilattice** | parity verdicts, coverage | `combine = max`: idempotent, commutative, associative ⟹ merge in any order |
| S19 | **Complete lattice + Knaster–Tarski** | `Discourse.grounded` | least fixed point **exists and is unique** |
| S20 | **Kleene ascent** | grounded, PageRank | the fixed point is *computed*, with a stated bound |
| S21 | **Galois connection** | tags ⇄ documents | faceted filtering is lattice meet; the concept lattice is derived |
| S22 | **Relation transpose** | backlinks | derived inverse ⟹ cannot go stale |
| S23 | **Kernel / partition** | `group by`, communities | disjoint and covering, for free |
| S24 | **Total order + tiebreak** | every ranking | determinism ⟹ the output is pinnable |
| S25 | **Closed sum type** | `Route.t`, `Ast.block`, `Query.op` | invalid states unrepresentable |
| S26 | **Phantom types** | `Id.'k t` | slug ≠ anchor ≠ block id, at compile time |

## 1. Identifiers — S25, S26

```ocaml
module Id : sig
  type page and anchor and block and term          (* phantom tags *)
  type 'k t = private string                       (* abstract *)
  val page   : string -> (page t,   Diagnostic.t) result  (* [a-z0-9_-] *)
  val anchor : string -> (anchor t, Diagnostic.t) result  (* [a-z0-9-]  *)
  val block  : string -> (block t,  Diagnostic.t) result  (* [A-Za-z0-9-], keeps ^ *)
  val term   : string -> (term t,   Diagnostic.t) result
  val show   : 'k t -> string
end
```

Discharges ontology **I2** (anchor and block namespaces disjoint) and **I4**
(unresolved cannot be coerced) at the type level. The underscore-alphabet defect
that bit the route parser becomes a compile error.

## 2. Effects — S7, S8, S9, S10, S11

The load-bearing decision of the whole atlas: **two different failure
structures, chosen per phase.**

```ocaml
module Validation : sig                (* APPLICATIVE — accumulates *)
  type 'a t = { value : 'a option; diags : Diagnostic.t list }
  val pure : 'a -> 'a t
  val ( <*> ) : ('a -> 'b) t -> 'a t -> 'b t
  val both : 'a t -> 'b t -> ('a * 'b) t
end                                    (* LAW: diags(a <*> b) = diags a @ diags b *)

module Res = Result                    (* MONAD — short-circuits *)

module Reader : sig type ('r,'a) t = 'r -> 'a  val bind : … end
module State  : sig type ('s,'a) t = 's -> 'a * 's  val bind : … end
```

- **Loading a corpus is applicative.** Documents are independent, so all
  diagnostics accumulate: a corpus with forty faults reports forty. Using a
  monad here would hide thirty-nine.
- **Parsing a query is monadic.** The first error is the answer; there is no
  second condition to check once the grammar broke.
- **Gates are monadic.** The first defect refuses.

This is not stylistic. Applicative-vs-monad here decides whether the system
reports one problem or all of them.

## 3. Dialect — S1, S2, S3, S4, S6, S14, S15, S16

```ocaml
module Ast : sig
  type inline = private string
  type block =
    | Inline_run of inline | Para of inline
    | Heading of { level : int; text : inline; pinned : Id.anchor Id.t option }
    | Rule
    | Fence of { lang : string option; meta : string option; body : string list }
    | List_block of { ordered : bool; start : int; content : list_content list }
    | Table of row list
    | Quote of block list
    | Callout of { kind : Callout.kind; title : inline option;
                   fold : [`Open|`Closed] option; body : block list }
    | Details of { summary : inline; body : block list }
    | Toc
    | Footnote_def of { label : string; body : block list }
    | Query_fence of Query.t
    | Literal_include of Include.spec
    | Diagram of { lang : [`Mermaid|`Dot]; source : string }
    | Math of { display : bool; source : string }
  and list_content = Item of item | Loose of block
  and item = { task : bool option; anchor : Id.block Id.t option; body : block list }
  and row  = { header : bool; cells : inline list }
  type t = block list

  (* S1: the pattern functor, made explicit so the schemes are real *)
  type 'a layer                                   (* block with children as 'a *)
  val map_layer : ('a -> 'b) -> 'a layer -> 'b layer
  val cata : ('a layer -> 'a) -> block -> 'a          (* S2 *)
  val para : ((block * 'a) layer -> 'a) -> block -> 'a (* S5 *)
  val parse : string -> t                              (* S4 = cata ∘ ana, TOTAL *)

  (* S6: one skeleton for every rewrite, in any applicative *)
  val traverse : (block -> block Validation.t) -> t -> t Validation.t

  (* S14/S15: optics over the tree *)
  val fences   : (block, Fence.t) Optic.traversal
  val headings : (block, Heading.t) Optic.traversal
  val prism_callout : (block, Callout.t) Optic.prism

  (* S16: ∂(Ast) — the one-hole context *)
  type context
  val zipper : t -> Id.block Id.t -> (block * context) option
  val rebuild : block -> context -> t
end
```

`cata` and `para` are the whole story for AST consumers:

| Consumer | Scheme | Why that one |
|---|---|---|
| `Render.to_` | **cata** (S2) | a target is an algebra; adding one never touches the parser |
| `anchors`, `depth`, `word_count` | **cata** | folds with no recursion written by hand |
| `Transclude.expand` | **para** (S5) | the step needs the *original* subtree to detect a cycle |
| every rewrite pass | **traverse** (S6) | one skeleton, diagnostics accumulate |
| block patching | **zipper** (S16) | patch one block; `∂` is exactly "document with a hole" |

S16 is the structure that makes block anchors more than a link target: with
`zipper`/`rebuild`, an agent can replace **one addressed block** and leave the
rest byte-identical — which is what keeps the render differential informative
after a machine edit.

```ocaml
module Render : sig
  type target = Html | Text | Slides
  type 'a algebra = 'a Ast.layer -> 'a
  val algebra : target -> resolve:Resolver.t -> string algebra
  val to_ : target -> resolve:Resolver.t -> Ast.t -> string   (* = cata (algebra …) *)
end
```

## 4. Addressing — S17, S25

```ocaml
module Resolver : sig
  type t                                           (* S17: partial-map monoid *)
  val empty : t
  val union : t -> t -> t                          (* left-biased; assoc, unit=empty *)
  val build : Document.t list -> t Validation.t
  val page  : t -> string -> Id.page Id.t option
  val typed : t -> kind:Ref.kind -> string ->
              (Id.page Id.t, [`None | `Ambiguous of int]) result
end

module Links : sig
  type ref_ = { target : Id.page Id.t; fragment : Id.anchor Id.t option }
  val outlinks  : Ast.t -> ref_ list               (* S15 traversal *)
  val fragments : Ast.t -> ref_ list
  val broken_paths   : Corpus.t -> Diagnostic.t list
  val broken_anchors : Corpus.t -> Diagnostic.t list      (* DISTINCT diagnosis *)
  val nitpick        : Corpus.t -> Diagnostic.t list
end

module Transclude : sig
  val expand : Corpus.t -> depth:int -> Ast.t -> Ast.t Validation.t  (* S5 + S7 *)
end

module Inventory : sig
  type entry = { name : string; kind : Ref.kind; uri : string }
  val publish : Corpus.t -> entry list
  val consume : path:string list -> t              (* S17 again: chain of maps *)
end
```

`Resolver` and `Inventory.consume` are the **same monoid** at two scales — local
keys and foreign inventories — which is why "look locally, then in each
inventory in order" is a `fold union` rather than a special case.

## 5. Graph — S12, S19, S20, S21, S22, S23, S24

```ocaml
module Corpus : sig
  type t
  type focused = { here : Document.t; all : t }    (* S12: Store comonad *)
  val extract : focused -> Document.t
  val extend  : (focused -> 'a) -> t -> (Id.page Id.t * 'a) list
end
```

S12 is the right structure for **every corpus-wide derivation**: backlinks,
mentions, similarity and correlated notes are all "compute this for the page in
focus", and `extend` lifts one such function to the whole corpus in one pass.
Writing them as ad-hoc folds is what lets them drift apart.

```ocaml
module Graph : sig
  type t
  val of_corpus : Corpus.t -> t
  val outlinks  : t -> Id.page Id.t -> Id.page Id.t list
  val transpose : t -> t                                        (* S22 *)
  val backlinks : t -> Id.page Id.t -> Id.page Id.t list        (* = outlinks ∘ transpose *)
  val back_ctx  : t -> Id.page Id.t -> (Id.page Id.t * string) list
  val mentions  : t -> Id.page Id.t -> Id.page Id.t list
  val typed     : t -> Id.page Id.t -> (Rel.t * Id.page Id.t) list
end

module Tags : sig                                   (* S21: Galois connection *)
  type context = { docs : Id.page Id.t list; tags : Tag.t list; inc : … }
  val members : context -> Tag.t -> Id.page Id.t list
  val tags_of : context -> Id.page Id.t -> Tag.t list
  val concepts : context -> (Tag.t list * Id.page Id.t list) list  (* closed sets *)
end

module Metrics : sig
  val pagerank    : Graph.t -> seed:(Id.page Id.t -> float) ->
                    (Id.page Id.t * float) list          (* S20 Kleene, bounded *)
  val communities : Graph.t -> (Id.page Id.t * Community.t) list  (* S23 + S24 *)
  val betweenness : Graph.t -> (Id.page Id.t * float) list
  val holes       : Graph.t -> (Community.t * Community.t) list
  val similarity  : Corpus.t -> Id.page Id.t -> (Id.page Id.t * float) list
end

module Discourse : sig                              (* S19 + S20 *)
  type af = { args : Id.page Id.t list; attacks : (Id.page Id.t * Id.page Id.t) list }
  val defends  : af -> Id.page Id.t list -> Id.page Id.t list   (* monotone F_AF *)
  val grounded : af -> Id.page Id.t list            (* lfp: Kleene ascent to fixpoint *)
  val anomalies : af -> Diagnostic.t list
end
```

`grounded` is the atlas's deepest structure: `defends` is monotone on the
powerset lattice of arguments, so by **Knaster–Tarski** its least fixed point
exists and is unique, and because the argument set is finite the **Kleene
ascent** `∅ ⊆ F(∅) ⊆ F²(∅) ⊆ …` reaches it in at most `|args|` steps. The
uniqueness is why it can answer "which claims stand" with one answer.

## 6. Query — S8, S9, S23, S24, S25

```ocaml
module Query : sig
  type _ field =                                    (* GADT: typing rule in the type *)
    | Status : string field | Type : string field | Group : string field
    | Slug   : string field | Tag  : string field
    | Words  : int field    | Degree : int field
    | Outlinks : int field  | Backlinks : int field
  type _ op = Eq : 'a op | Ne : string op          (* Ne only on string *)
            | Lt : int op | Le : int op | Gt : int op | Ge : int op
  type cond = Cond : 'a field * 'a op * 'a -> cond  (* existential, well-typed *)

  type t = { conds : cond list; group_by : string field option;
             sort : sort_key * bool; limit : int option }
  val parse : string -> (t, Diagnostic.t) result    (* S8, named errors *)
  val eval  : (Corpus.t, Document.t list) Reader.t  (* S9, pure *)
  val group : Corpus.t -> t -> (string * Document.t list) list  (* S23 *)
end
```

The GADT is the point: `Ne : string op` makes `where words != 3`
**unrepresentable in the AST**, so the parser's named type error is the only way
such a query can appear — and the evaluator needs no defensive case for it.
That is S25 doing work a runtime check would otherwise do.

## 7. Surface and verification — S18, S24, S25

```ocaml
module Route : sig
  type t = Index | Note of Id.page Id.t | Component of Id.page Id.t
         | Query_console | Search of string
         | Asset of { stem : string; ext : Asset.ext } | Api of Api.t
  val of_path : string -> t option
  val to_path : t -> string                        (* LAW: of_path ∘ to_path = Some *)
end

module Verdict : sig                                (* S18 *)
  type t = Verified | Unmapped | Blocked | Divergent
  val combine : t -> t -> t                        (* max-rank: idempotent, comm, assoc *)
  val zero : t                                     (* Verified is the unit *)
end

module Differential : sig
  type verdict = Checked | Drifted of Digest.t * Digest.t | Edited_since | Unlisted
  val compare : pinned:(Digest.t * Digest.t * string) list -> Corpus.t ->
                (string * verdict) list
end

module Doctest : sig
  type block = { group : string; kind : [`Setup|`Code|`Output|`Cleanup];
                 skip_if : string option; body : string }
  val collect : Corpus.t -> block list             (* S15 traversal over fences *)
  val run : block list -> (string * Outcome.t) list
end

module Ratchet : sig
  (* the real signature is INCLUDED below, not copied — see the note *)
end
```

`Ratchet.check` is the first signature on this page quoted by
**inclusion rather than by copy** (HW.9.2.1): the block below is a slice of
`modules/hermes_wiki/src/control/ratchet.mli` selected by durable markers, so
its denotation *is* the file and it cannot drift from the code it documents.
Every other signature above is still a hand-copy, and the survey that motivated
this feature found most of them already drifted — those are the conversion
backlog.

```literalinclude modules/hermes_wiki/src/control/ratchet.mli start-after=Breached end-before=judge dedent lang=ocaml
```

*Second-pass note (S37):* `Verdict.combine` is one instance of the graded
chain — a keep-worst fold over a bounded join-semilattice — and its empty
policy (`zero = Verified` as the unit) is a **site declaration, not a
consequence of the algebra**: the parity-evidence site declares the opposite
("an empty required node is unmapped, not verified", the vacuous-truth leg
`test_parity_algebra` pins). See `[[Unified system synthesis]]`.

## 8. The module DAG

```
Id · Diagnostic · Validation · Reader · State · Optic     (foundations)
 └── Meta ── Document ── Corpus (Store comonad)
      ├── Ast (initial algebra; cata/para/traverse/zipper) ── Render (algebras)
      ├── Resolver (partial-map monoid) ── Links ── Transclude (para)
      ├── Graph (transpose) ── Tags (Galois) ── Metrics (Kleene) ── Discourse (lfp)
      ├── Query (GADT) ── Nav ── Search ── Inventory
      └── Route ── Serve                        ◀ IO
            Differential · Doctest · Doc_coverage · Ratchet   ◀ IO
```

Acyclic; exactly three leaves touch the world (`Corpus_io`, `Serve`,
`Verify_io`). Everything above is a pure function of values — which is the
precondition for property tests, solver encodings and the differential.

## 9. Coverage check — entities and relations

| Entity | Function | Entity | Function |
|---|---|---|---|
| E1–E2 | `Corpus_io`, `Document` | E13–E14 | `Links` |
| E3–E5 | `Id`, `Meta` | E15–E16 | `Graph.typed`, `Tags` |
| E6–E9 | `Document`, `Meta` | E17 | `Nav.node` |
| E10 | `Ast.block` | E18 | `Query` |
| E11–E12 | `Id.anchor`, `Id.block` | E19–E20 | `Inventory` |
| E21 | `Doctest.block` | E22 | `Diagnostic` |
| E23 | `Differential` | | |

| Relation | Function | Relation | Function |
|---|---|---|---|
| R1–R3 | `Document.slug_of`, `group_of` | R11 | `Links.broken_anchors` |
| R4 | `Resolver.page` | R12 | `Resolver.typed` |
| R5–R6 | `Ast.parse`, `Ast.anchors` | R13 | `Transclude.expand` |
| R7–R10 | `Graph.*`, `Corpus.extend` | R14 | `Tags` |
| R16 | `Query.eval` | R15 | `Nav.unreachable` |
| R17 | `Discourse.grounded` | R18 | `Differential` |
| R19–R20 | `Route`, `Doctest` | | |

**23 entities, 20 relations, 26 structures — all present.**

## 10. Structures deliberately rejected

| Structure | Where it would fit | Why rejected |
|---|---|---|
| **Free monad** | an extensible block/command DSL | an open constructor set makes `render` non-total; our `Ast.block` is closed on purpose |
| **Coinductive `ν`, streams** | an infinite/lazy corpus | the corpus is finite and enumerated by `git ls-files`; laziness would break determinism of the digest |
| **Profunctor optics** | a fully general optic library | our optics are used monomorphically over `Ast`; van Laarhoven traversals suffice, and the extra generality costs readability |
| **Monad transformers stack** | combining Reader+State+Writer | explicit parameter passing keeps signatures readable and the effects auditable; there are only three effects and they rarely combine |
| **Lens on `Ast`** | editing arbitrary nodes | superseded by the zipper (S16), which is the *right* structure for one-hole editing |
| **Semiring / tropical algebra** | shortest-path scoring | betweenness needs counts and BFS, not a semiring generalisation we would never instantiate twice |
| **One global severity carrier** | merging alerts, verdicts, severities and strengths onto one `level = int` with one `worst` | the rank isomorphisms become *coercions*: `alert → verdict` typechecks and R5 violations compile; the isomorphism must exist mathematically and **not** syntactically (`test_smtml_alerts`); S37 shares the schema, never the carrier — `[[Unified system synthesis]]` §10.2 |

Recording rejections matters: each is a structure a reader might otherwise
expect, and the reason is a design constraint rather than an oversight.

Cross-references: `[[Unified domain ontology]]` · `[[Unified functional algebra]]` ·
`[[Unified implementation approach]]` · `[[Unified feature set]]` ·
`[[Unified mathematical structures]]`.

Part of [[Knowledge fractal map]].

## Declarative configuration projection

The R23 configuration slice is derived from `Ops_config.elements` and keeps
declaration, observation, digest identity, admission, execution, scheduling,
and evidence as distinct authorities:

- [[declarative-intent-config-ontology]]
- [[declarative-intent-config-fractal-atlas]]
- [[declarative-intent-config-fractal-algebra]]
