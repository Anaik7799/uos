---
id: hermes-unified-fractal-atlas
status: published
type: reference
ktype: moc
maturity: incubating
domain: formal_verification
topics: [fractal, atlas, control-flow, data-flow]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Unified fractal atlas — the six systems on one map

#feature #src-unified #area-atlas #cov-analysis

Static structure, control flow, data flow and the verification frontier, with
all six overlaid. Entities in `[[Unified fractal ontology]]`; laws in
`[[Unified fractal algebra]]`; the explanation in `[[Meta-unification]]`.

## 1. The unified static map

```
U0 Realm      workspace · vault · site · project · 空间 · repo
 │
U1 Container  teamspace │ folder⁰ │ content-set │ — │ 知识库¹ │ corpus-root⁰
 │                ⁰ non-semantic          ¹ TOTAL: no document outside it
U2 Ordering   — │ — │ sidebar_position │ toctree │ 目录(data+attrs) │ ✗HW.6.8.1
 │
U3 Document   page≡block │ note(file) │ MDX │ document │ 文稿×4 │ page×1
 │                                                        (kind typed)
U4 Section    heading │ #H, #H1#H2 │ {#id} │ :ref: label │ heading │ anchor
 │
U5 Statement  block │ ^blockid │ — │ domain object │ 卡片 │ ✗HW.3.3.1
 │
U6 Field      property │ frontmatter │ 21 fields │ field list │ property │ 11
 │
UX Foreign    — │ — │ — │ objects.inv │ — │ ✗HW.3.8.1
```

Two columns of `✗` are the harness's open structural holes; both are register
items, and both are now unblocked.

## 2. The control-flow spectrum — where the gate can stand

Ordered by *how much happens between authoring and reading*, because that gap
is the only place a verifier can attach.

```
NO GAP ─────────────────────────────────────────────────▶ WIDE GAP

Notion            Yuque             Obsidian         Docusaurus/Sphinx/Hermes
live blocks       draft→publish     file→index       source→build→output
     │                 │                 │                    │
  no build        publish is a       index is         a BUILD exists:
  no gate         state change      disposable       a gate can stand here
                  (still no gate)   (no gate used)
                                                     ┌──────────────────────┐
                                                     │ Docusaurus: links    │
                                                     │ Sphinx: refs·doctest │
                                                     │        ·coverage     │
                                                     │ Hermes: DIGEST       │
                                                     └──────────────────────┘
```

This diagram is the atlas's central claim. **Verification is not a feature a
tool chose to skip; it is a possibility its control flow either offers or
forecloses.** Notion cannot have a render differential — there is no render
step to differentiate. Obsidian could and does not. Sphinx and Hermes both do,
along different axes.
*Second-pass line (S36):* every viable gate position in this spectrum is an
**S36 equalizer** — declared vs derived, reconciled at that seam — which is
*why* Notion's no-build-step topology has nowhere to stand one: no seam, no
pair to reconcile (`[[Unified system synthesis]]`).

## 3. The data-flow inversion

```
RICH CANONICAL (Notion, Yuque)          PLAIN CANONICAL (Obsidian, Docusaurus,
                                                          Sphinx, Hermes)
   blocks / Lake  (hosted)                  markdown / reST  (in git)
        │ project (LOSSY)                        │ parse
   ┌────┼────┬─────┐                             ▼
   ▼    ▼    ▼     ▼                          AST (recursive)
  md  html  pdf  views                           │ render
                                        ┌────────┼────────┐
  ✗ no canonical serialisation          ▼        ▼        ▼
  ✗ digest is not a statement          HTML    text     JSON
    about content                       │
                                        ▼
                                  ✓ digest(render(parse d)) IS a
                                    statement about content
```

The right-hand side is not merely a preference. It is the precondition for
every gate in the harness, and it is why "markdown as export" and "markdown as
source" are different guarantees rather than different words.

## 4. The verification frontier

What each system checks, and what fails the build:

| Check | N | O | D | S | Y | Hermes |
|---|---|---|---|---|---|---|
| dead internal link | — | shown | **fails** | **fails** | — | **fails** |
| dead **anchor** | — | — | **fails** | **fails** | — | **reports** ✓ |
| ambiguous reference | — | — | — | **fails** (`:any:`) | — | notice at definition |
| unresolved reference (any kind) | — | — | — | **fails** (nitpicky) | — | ✗ |
| unreachable document | — | orphan list | — | **fails** unless `:orphan:` | — | anomaly |
| external URL rot | — | — | — | **linkcheck** | — | ✗ HW.8.2.5 |
| **documentation executes** | — | — | — | **doctest** | — | ✗ HW.9.3.* |
| **documentation coverage** | — | — | — | **coverage** | — | formal only |
| **render is byte-stable** | — | — | — | — | — | **✓ only here** |
| determinism of rankings | — | — | — | — | — | **✓ only here** |
| law + mutation legs | — | — | — | — | — | **✓ only here** |

Reading down the Sphinx column gives a maturity ladder we are climbing; reading
the last three rows gives the axis nobody else is on.

## 5. The derivation frontier — what is computed, not stored

| Derived thing | N | O | D | S | Y | Hermes |
|---|---|---|---|---|---|---|
| backlinks | ✓ | ✓ | — | — | — | ✓ + citing line |
| unlinked mentions | — | ✓ | — | — | — | ✓ |
| rows from a query | ✓ | ✓ | — | — | *(stored)* | ✓ |
| aggregates | ✓ rollup | ✓ | — | — | ✓ | ✗ HW.4.6.3 |
| centrality / clusters | — | ✓ plugin | — | — | — | ✗ HW.4.2.* |
| **grounded standing** | — | — | — | — | — | ✗ HW.4.4.1 — **nowhere else** |
| toc / anchors | ✓ | ✓ | ✓ | ✓ | *(authored)* | ✓ |
| navigation order | — | — | *(authored)* | *(authored)* | *(authored)* | derived |

Yuque and the doc generators **author** what the knowledge tools **derive**.
Neither is wrong: authored order is a decision, derived order is a fact. The
harness derives order and should gain the authored option (HW.6.8.1) — the two
coexist, as Sphinx shows.

## 6. Where each tool's map is deepest

```
Notion      ████████░░  block recursion, database views      (F5 Derivation)
Obsidian    ████████░░  addressing ladder, link graph        (F2, F3)
Docusaurus  ██████░░░░  routing, reference integrity, AST    (F2, F6-partial)
Sphinx      ██████████  reference typing + verification      (F6)
Yuque       ████████░░  containment, canonical projection    (F1, F4)
Hermes      ██████████  evidence: digest, laws, mutation     (F6, own axis)
```

No tool is deep everywhere, and the shallow parts are predictable from the deep
one — which is the subject of `[[Meta-unification]]`.

## 7. Atlas verdict

1. **The gate's existence is a control-flow property**, not a diligence
   property (§2).
2. **A rich canonical form and a differential gate are mutually exclusive**
   (§3), so the harness's plainness is load-bearing rather than austere.
3. **Sphinx is the maturity ladder** for reference and executability (§4);
   **Obsidian is the ladder** for addressing granularity; **Notion** for
   derivation; **Yuque** for containment and projection discipline.
4. **Three rows have one occupant** — byte-stable render, determinism of
   rankings, law+mutation. Those are not gaps in the others; they are a
   different purpose.

Cross-references: `[[Unified fractal ontology]]` · `[[Unified fractal algebra]]` ·
`[[Unified mathematical structures]]` · `[[Meta-unification]]`.

Part of [[Knowledge fractal map]].
