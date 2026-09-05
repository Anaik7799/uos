---
id: hermes-unified-fractal-ontology
status: published
type: reference
ktype: moc
maturity: incubating
domain: formal_verification
topics: [fractal, ontology, levels, modal-strength]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Unified fractal ontology — Notion · Obsidian · Docusaurus · Sphinx · Yuque · Hermes

#feature #src-unified #area-ontology #cov-analysis

The five comparators plus this harness, as **one ontology with six
presentations**. Companions: `[[Unified fractal atlas]]`,
`[[Unified fractal algebra]]`, `[[Unified mathematical structures]]`, and the
view that explains the whole family, `[[Meta-unification]]`.

**Method — a colimit, not an intersection.** Unifying by keeping only what all
six share would discard exactly the interesting parts. Instead each tool is
treated as a *theory*, shared sub-theories are identified, and the union is
taken along them. Nothing is dropped: where two tools disagree, **both answers
are recorded with the constraint that forces each**. Per-tool detail lives in
the fifteen source documents and is referenced, never summarised away.

## 1. The unified level lattice

Every tool's levels embed into one seven-level lattice. `—` means the tool has
no entity at that level, which is itself information.

| U | Level | Notion | Obsidian | Docusaurus | Sphinx | Yuque | Hermes |
|---|---|---|---|---|---|---|---|
| **U0** | Realm | Workspace | Vault | Site | Project | 空间 Space | Repo |
| **U1** | Container | Teamspace | Folder *(non-semantic)* | Plugin content set | — | **知识库 Base (total)** | Corpus root |
| **U2** | Ordering | — | — | sidebar + `sidebar_position` | **toctree** | **目录 TOC (data + attrs)** | — *(HW.6.8.1)* |
| **U3** | Document | Page ≡ Block | Note (a file) | MDX document | Document | 文稿 (4 kinds) | Page (1 kind) |
| **U4** | Section | heading block | Heading *(nestable)* | heading + `{#id}` | **label / `:ref:`** | heading | heading + anchor |
| **U5** | Statement | block | **`^blockid`** | — | **domain object** | 卡片 card | — *(HW.3.3.1)* |
| **U6** | Field | Property | frontmatter | 21 frontmatter fields | field list | properties | frontmatter (11) |
| **UX** | Foreign | — | — | — | **`objects.inv`** | — | — *(HW.3.8.1)* |

Three readings of this table:

- **U1 varies in force, not shape.** Everyone has a container; only Yuque makes
  membership **total** (a document cannot exist outside a base). Obsidian makes
  it explicitly *non-semantic*. Hermes derives it. Same entity, three different
  modal strengths — and that difference, not the entity, is the design.
- **U2 and U5 are where tools are missing entities.** Ordering is absent from
  Notion and Obsidian; statement-level addressing is absent from Docusaurus and
  Hermes. These are the two levels where the survey has genuine holes.
- **UX exists once.** Only Sphinx's ontology extends past its own corpus.
- **Caution (second pass, R9).** The U-levels and the evidence chain's
  L-levels admit **no identification** (`[[Unified system synthesis]]` §10.1):
  the two sites carry opposite empty-cover policies, and LX has no image. This
  lattice compares tools; it does not map fractals.

## 2. The six entity families, unified

Every feature in all six tools falls into exactly one family. This is the
partition that makes the register's ten `HW.*` areas and the five tools
commensurable.

| Family | What it answers | Primitive in |
|---|---|---|
| **F1 Containment** | where does this live, and must it? | Yuque |
| **F2 Addressing** | how do I point at it, and how finely? | Obsidian |
| **F3 Graph** | what does it connect to, and what follows? | Obsidian *(Hermes for discourse)* |
| **F4 Projection** | which form is the truth, and what derives from it? | Yuque *(inverted in Obsidian, Hermes)* |
| **F5 Derivation** | what is computed rather than stored? | Notion |
| **F6 Verification** | what is checked, and what fails the build? | **Sphinx · Hermes** |

The families are ordered by dependency: you cannot address what is not
contained, cannot build a graph without addressing, cannot project without a
carrier, cannot derive without a graph or a schema, and **cannot verify
anything you have not first made canonical**. F6 depends on F4 having chosen a
serialisable truth — which is the single deepest fact in this ontology and is
proved in `[[Unified fractal algebra]]` §4.

## 3. The relation catalogue (nothing dropped)

| Relation | Notion | Obsidian | Docusaurus | Sphinx | Yuque | Hermes |
|---|---|---|---|---|---|---|
| container ∋ document | teamspace | folder (weak) | content set | — | **total** | derived group |
| document ≺ document (order) | — | — | sidebar_position | toctree | TOC node | — |
| document → document (link) | mention | `[[…]]` | md link | `:doc:` | link | `[[…]]` |
| ← inverse (backlink) | ✓ derived | ✓ derived | — | — | — | ✓ derived + citing line |
| document ⇢ section | — | `#H`, `#H1#H2` | `#id`, `{#id}` | `:ref:` | — | `#anchor` |
| document ⇢ statement | block ref | **`#^id`** | — | domain object | card | HW.3.3.1 |
| typed edge | **relation** | `[[T\|@rel]]` | — | domain kind | — | `[[T\|@rel]]` |
| embed / transclude | synced block | `![[…]]` | — | `literalinclude` | card | HW.3.5.* |
| aggregate / fold | **rollup** | Dataview | — | — | data table | MoC, HW.4.6.3 |
| query → rows | **database view** | Dataview / Bases | — | — | data table | **zkquery** |
| canonical → projection | blocks→md | *(none — md IS canonical)* | *(none)* | *(none)* | **Lake→md** | *(none)* |
| document ⊨ code | — | — | — | **doctest** | — | HW.9.3.* |
| reference ⊨ target | — | — | **path + anchor** | **nitpicky, typed** | — | link ✓, anchor ✓ |
| corpus ⊨ digest | — | — | — | — | — | **render differential** |
| project ⇄ project | — | — | — | **intersphinx** | — | HW.3.8.* |

The last three rows are the ones with a single occupant, and they are the
harness's reason to exist: **`corpus ⊨ digest` exists nowhere else in the
survey.**

## 4. Modal strength — the axis nobody states explicitly

The same relation appears at four different strengths across the tools, and
this is the most transferable idea in the whole ontology:

| Strength | Meaning | Example |
|---|---|---|
| **derived** | computed from something else; cannot go stale | backlinks (everyone), Hermes `group` |
| **declared** | authored, and believed | `sidebar_position`, TOC node |
| **enforced** | the system refuses states that violate it | Yuque containment, Sphinx nitpicky |
| **type-level** | violating states are *unrepresentable* | Hermes route ADT (no write verb), TyXML markup |

Reading any feature by its strength rather than its name is what makes the six
tools comparable. Hermes is the only one that reaches the fourth level, and it
reaches it in exactly two places — the route ADT and typed markup. Every other
guarantee we have is *enforced*, which is one rung weaker, and the register's
laws are what hold that rung.
*Second-pass addendum:* the strength order now has an **executable form** —
S36's `status`/`residue` (`[[Unified system synthesis]]` §13), probe over
declaration by construction — mirroring `[[Unified domain ontology]]` §0 so
the analytical and normative tables stay aligned.

## 5. Where the six ontologies genuinely conflict

Not differences of coverage — conflicts, where adopting one forecloses another.

1. **Canonical richness vs. differential verification.** Yuque and Notion make
   the canonical form rich (Lake, blocks). Obsidian, Docusaurus, Sphinx and
   Hermes make it source text. You may have a digest gate or a rich canonical
   form, **not both** — proved in the algebra §4.
2. **Total containment vs. stable identity.** Yuque's `place` is total, so
   moving a document changes its base. Hermes's `slug ∘ move_dir = slug`, so
   moving changes nothing — but then containment cannot be a constraint.
3. **Live editing vs. reviewable history.** Real-time co-editing removes the
   commit; the commit is what makes review and the audit trail possible.
4. **Extension surface vs. provable properties.** Plugins (Obsidian), cards
   (Yuque), MDX (Docusaurus) and extensions (Sphinx) all buy expressiveness by
   giving up totality of the render.
5. **Generation vs. evidence.** A model in the authoring path means a document
   is no longer a function of its inputs — see the algebra §8.

Each conflict is a genuine fork, and in each the harness has chosen the
right-hand side because it is a *parity harness*: its output must be evidence.

## 6. What the unified ontology adds that no single view had

- **The modal-strength axis** (§4) — a vocabulary for comparing guarantees
  rather than features.
- **The family dependency order** (§2) — why verification is last, and why a
  tool that never made its form canonical cannot bolt verification on.
- **The empty cells** — U2 and U5 are the survey's structural holes, and both
  are open register items (HW.6.8.1, HW.3.3.1).
- **The single-occupant rows** (§3) — `corpus ⊨ digest`, `document ⊨ code`,
  `project ⇄ project`. Two of the three are ours to build.

Cross-references: `[[Unified fractal atlas]]` · `[[Unified fractal algebra]]` ·
`[[Unified mathematical structures]]` · `[[Meta-unification]]` · the five
per-tool triples · `docs/hermes/features-audit-implementation-plan.md`.

Part of [[Knowledge fractal map]].
