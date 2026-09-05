---
id: hermes-unified-fractal-algebra
status: published
type: reference
ktype: moc
maturity: incubating
domain: formal_verification
topics: [fractal, algebra, family-laws, scoreboard]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Unified fractal algebra — one algebra per family, six instantiations

#feature #src-unified #area-algebra #cov-analysis

Carrier · operation · identity · absorbing · laws, per **family** rather than
per tool, with each tool's instantiation recorded underneath. The six families
are defined in `[[Unified fractal ontology]]` §2; the structures they use are
named in `[[Unified mathematical structures]]`.

Where a tool violates a family law, it is recorded. **A violated law is
information**, and dropping it would be the lossy summary this document exists
to avoid.

---

## F1 · Containment

- **Carrier** documents, containers
- **Operation** `place : doc → container → doc`
- **Identity** none where containment is total; the "no container" state
  otherwise
- **Absorbing** none
- **Laws**
  - *(L1.1) uniqueness* `∀d. |{c : contains(c,d)}| ≤ 1`
  - *(L1.2) totality* `∀d. ∃c. contains(c,d)` — **optional**, and the whole
    design question
  - *(L1.3) scope inheritance* permission, publication and search scope descend
  - *(L1.4) exemption* a total rule needs a **named** escape hatch to be liveable

| Tool | L1.1 | L1.2 | Notes |
|---|---|---|---|
| Notion | ✓ | ✗ | pages may be top-level |
| Obsidian | ✓ | ✗ | folders explicitly non-semantic — a *stated* rejection of L1.2 |
| Docusaurus | ✓ | ✓ within a content set | plugin sets partition the corpus |
| Sphinx | ✓ | ✗ | toctree orders; it does not contain |
| **Yuque** | ✓ | **✓ enforced** | + L1.4 via 小记 quick notes |
| Hermes | ✓ | ✗ | group is derived; `slug ∘ move_dir = slug` instead |

**The trade, stated once.** L1.2 and *stable identity under move* are
incompatible: if the container is part of what a document is, moving it changes
the document. Yuque took containment; we took identity. Neither is free.

---

## F2 · Addressing

- **Carrier** `Address`, at whatever granularity the tool offers
- **Operation** `resolve : Address ⇀ Target` (**partial**)
- **Identity** the local self-address
- **Absorbing** an unresolvable address
- **Laws**
  - *(L2.1) visible failure* unresolved renders **distinctly**, never silently
  - *(L2.2) namespace disjointness* pinned ids and generated anchors cannot
    collide *by construction* (Obsidian keeps `^`; Sphinx uses domains)
  - *(L2.3) alphabet honesty* different namespaces have different alphabets and
    a parser must not assume one
  - *(L2.4) locality* `anchors(render_single d) = anchors(render_corpus d)`
  - *(L2.5) unique resolution* `|resolve(x)| = 1`; `0` and `>1` reported
    **distinctly**
  - *(L2.6) stability* a pinned id survives edits a derived anchor does not

| Tool | L2.1 | L2.2 | L2.5 | Deepest granularity |
|---|---|---|---|---|
| Notion | ✓ | n/a | ✓ (ids) | block |
| **Obsidian** | ✓ | ✓ `^` | ✗ | **statement `^id`** |
| Docusaurus | ✓ | ✓ `{#id}` | ✗ | section |
| **Sphinx** | ✓ | ✓ domains | **✓ `:any:`** | typed object |
| Yuque | ✓ | n/a | ✗ | card |
| Hermes | ✓ | pending HW.3.3.1 | ✗ *(notice at definition)* | section |

L2.5 has one full occupant. Sphinx errors at the **use** site, which is where
the reader is harmed; ours reports at the definition site and is silent at use.
That gap is HW.3.7.2.

---

## F3 · Graph

- **Carrier** a directed, optionally labelled multigraph over documents
- **Operation** edge composition; inverse
- **Identity** the empty edge set
- **Absorbing** none
- **Laws**
  - *(L3.1) inverse is derived* `b ∈ back(a) ⟺ a ∈ out(b)` — never stored
  - *(L3.2) mention complement* `mentions(a) ∩ backlinks(a) = ∅`
  - *(L3.3) external exclusion* an off-corpus URL is not an edge
  - *(L3.4) typed edges render both ways*
  - *(L3.5) determinism of derived metrics* — layout, ranking, clustering must
    be reproducible or a digest gate over them is meaningless
  - *(L3.6) grounded standing* the least fixed point of the defence operator is
    unique (Knaster–Tarski)

| Tool | L3.1 | L3.2 | L3.4 | L3.5 | L3.6 |
|---|---|---|---|---|---|
| Notion | ✓ | ✗ | ✓ relations | n/a | ✗ |
| **Obsidian** | ✓ | **✓** | ✓ | ✗ *(LPA is random)* | ✗ |
| Docusaurus | ✗ no graph | — | — | — | — |
| Sphinx | ✗ | — | ✓ domains | — | — |
| Yuque | ✗ | — | — | — | — |
| **Hermes** | ✓ **+ citing line** | ✓ | ✓ | ✓ **required** | ✗ **HW.4.4.1** |

L3.5 is ours alone as a *requirement*: label propagation is non-deterministic by
construction (random sweep, random tie-break), so we need a **constrained**
variant with a total order on vertices and labels. Obsidian's plugins do not
need this because nothing pins their output.

L3.6 has **no occupant anywhere**. It is the deepest open item in the register.

---

## F4 · Projection

- **Carrier** document bodies in several forms
- **Operation** `project : Canonical → Format → Body`
- **Identity** the canonical form under identity projection
- **Absorbing** none
- **Laws**
  - *(L4.1) canonicity* one form is authoritative; all others are functions of it
  - *(L4.2) projection loss* a projection preserves only what the target can
    name — `parse ∘ project ≠ id` in general
  - *(L4.3) target agreement* every render target denotes the same content
  - *(L4.4) serialisability* the canonical form has a **canonical serialisation**

| Tool | Canonical | L4.2 direction | **L4.4** | Digest gate possible? |
|---|---|---|---|---|
| Notion | hosted blocks | blocks → md, lossy | ✗ | **no** |
| Yuque | Lake | Lake → md, lossy | ✗ | **no** |
| Obsidian | markdown | md → render, lossy | ✓ | yes — unused |
| Docusaurus | MDX source | source → HTML | ✓ | yes — unused |
| Sphinx | reST/MyST source | source → builders | ✓ | yes — unused |
| **Hermes** | markdown | md → HTML/text/JSON | ✓ | **yes — used** |

L4.4 is the hinge of the entire survey, and its proof is in
`[[Unified mathematical structures]]` §4. Two tools cannot satisfy it; three can
and do not; one does.

L4.3 is Yuque's demonstrated law — presentation mode is a second render target
of one source. Ours is the same law stated for the text builder (HW.6.9.3).

---

## F5 · Derivation

- **Carrier** stored facts; derived views
- **Operation** `derive : Corpus → View`
- **Identity** the identity view (the corpus itself)
- **Absorbing** an empty selection
- **Laws**
  - *(L5.1) purity* `derive` depends only on the corpus
  - *(L5.2) commuting filters* `filter a ∘ filter b = filter b ∘ filter a`
  - *(L5.3) partition* `group by f` is the kernel of `f` — disjoint and covering
  - *(L5.4) prefix monotonicity* `limit n` is a prefix of `limit m`, `m ≥ n`
  - *(L5.5) one denotation* all view modes render the same rows
  - *(L5.6) totality* a malformed query is a **named error**, never a silently
    empty result
  - *(L5.7) fold order-independence* aggregates are monoid homomorphisms

| Tool | L5.1 | L5.3 | L5.5 | **L5.6** | L5.7 |
|---|---|---|---|---|---|
| Notion | ✗ formulas | ✓ | ✓ | ✓ UI-constrained | ✓ rollup |
| Obsidian Dataview | ✗ JS | ✓ | ✓ | ✗ **JS may throw** | ✓ |
| Obsidian Bases | ✓ | ✓ | ✓ | ~ | ✓ |
| Yuque data table | *(stored)* | ✓ | ✓ | ~ | ✓ |
| **Hermes** | **✓** | **✓** | **✓** | **✓ proved** | ✗ HW.4.6.3 |

L5.6 is where we are strictly strongest, and `test_wiki_query` proves it: every
input yields `Ok` or a *named* `Error`. An empty result always means "no
matches" — never "your query was malformed", which looks like an answer.

---

## F6 · Verification

- **Carrier** claims about the corpus
- **Operation** `check : Corpus → Diag list`
- **Identity** the vacuous check (no claims)
- **Absorbing** a **defect** — it refuses the build
- **Laws**
  - *(L6.1) severity split* a defect refuses; a notice reports. **A notice must
    never refuse** — a gate that cries wolf gets bypassed
  - *(L6.2) disclosed exception* strictness with a per-instance opt-out that
    **leaves a mark** (`:orphan:`, `!ref`, `:skipif:`, `allow_example_links`)
  - *(L6.3) fail-closed* unknown or unmeasurable ⟹ **not** passing
  - *(L6.4) distinct diagnoses* different fixes ⟹ different diagnostics
  - *(L6.5) both directions* a check must be shown to **fail** when the property
    is broken, not merely to pass
  - *(L6.6) ratchet* the count of known-open findings is **monotone
    non-increasing**
  - *(L6.7) no silent caps* anything skipped or truncated is **named**

*Second-pass instances* (`[[Unified system synthesis]]`): the gate law is an
**S36** reconciliation — declared vs derived at the seam, residue = the
diagnostic list; the verdict merge is an **S37** graded chain — keep-worst
join with a site-declared empty policy; determinism (F3's L3.5) is **S40**'s
L40.3 — one world per battery run.

| Tool | L6.1 | L6.2 | L6.4 | **L6.5** | **L6.6** |
|---|---|---|---|---|---|
| Notion | — | — | — | — | — |
| Obsidian | — | — | — | — | — |
| Docusaurus | ✓ | ✓ | **✓ path vs anchor** | ✗ | ✗ |
| **Sphinx** | ✓ | **✓ three forms** | ✓ | ✗ | **✓ `-W`** |
| Yuque | — | — | — | — | — |
| **Hermes** | ✓ | ✓ | ✓ | **✓ mutation legs** | ✗ **HW.10.2.1** |

L6.5 is ours alone: every law landed this session was checked by breaking the
implementation and confirming the test fails — and that discipline caught a hole
in my own tests (the dead-anchor/dead-link conflation survived three mutants).

L6.6 is Sphinx's and not ours. Our severity split is the right *classification*;
what is missing is the ratchet that stops the notice count growing.

---

## 7. The law scoreboard

| Family | Laws | Hermes holds | Open |
|---|---|---|---|
| F1 Containment | 4 | 2 | L1.2, L1.4 — *deliberately declined* |
| F2 Addressing | 6 | 4 | L2.2 (HW.3.3.1), L2.5 (HW.3.7.2) |
| F3 Graph | 6 | 4 | L3.5 partial, L3.6 (HW.4.4.1) |
| F4 Projection | 4 | **4** | — |
| F5 Derivation | 7 | 6 | L5.7 (HW.4.6.3) |
| F6 Verification | 7 | 6 | L6.6 (HW.10.2.1) |

Recounted by **law id** after the second-pass annotations (a hand count is
exactly the drift S42's L42.3 exists to gate — and it had drifted: the first
tally said 24):

- **Held, 26**: L1.1, L1.3 · L2.1, L2.3, L2.4, L2.6 · L3.1–L3.4 · L4.1–L4.4 ·
  L5.1–L5.6 · L6.1–L6.5, L6.7.
- **Open, 6, each with its register id**: L2.2 (HW.3.3.1), L2.5 (HW.3.7.2),
  L3.5 partial, L3.6 (HW.4.4.1), L5.7 (HW.4.6.3), L6.6 (HW.10.2.1).
- **Declined, 2, with reasons**: L1.2, L1.4.

26 + 6 + 2 = 34. F4 is the only family held completely, and it is the one the
digest gate depends on.

Cross-references: `[[Unified fractal ontology]]` · `[[Unified fractal atlas]]` ·
`[[Unified mathematical structures]]` · `[[Meta-unification]]` · the five
per-tool algebra documents.

Part of [[Knowledge fractal map]].
