---
id: hermes-sphinx-fractal-ontology
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Sphinx — fractal ontology

#feature #src-sphinx #area-ontology #cov-analysis

## 1. The level structure

Sphinx's fractal is over **reference**: every level is something a
cross-reference can point at, and every pointer is checked.

| Level | Entity | Unit of | Referenced by |
|---|---|---|---|
| **S0** | Project | configuration, build | — |
| **S1** | Document | a file in the toctree | `:doc:` |
| **S2** | Section / label | an anchor | `:ref:` |
| **S3** | Object (domain-typed) | a described entity | `:py:class:`, `:cpp:func:`, … |
| **S4** | Term | glossary vocabulary | `:term:` |
| **SX** | External project | another doc set | intersphinx via `objects.inv` |

The load-bearing fact: **SX**. Sphinx is the only comparator whose ontology
extends past its own corpus. `objects.inv` publishes a name→URI inventory so a
foreign project resolves references into yours *without knowing your layout*.

Second load-bearing fact: **S3 is domain-typed**. A reference declares what
kind of thing it expects, so `py:class:Foo` and `cpp:class:Foo` cannot collide
and a wrong resolution is *detectable* rather than merely plausible.

## 2. Entity families

**Source** — reStructuredText or MyST markdown; directives (block) and roles
(inline) are the two extension points, both closed and named.

**Structure** — `toctree` declares hierarchy in content, with `:maxdepth:`,
`:glob:`, `:hidden:`, `:numbered:`, `:titlesonly:`. A document unreachable from
any toctree is reported unless it declares `:orphan:`.

**Domains** — Python, C, C++, JavaScript, reStructuredText: each supplies
object-description directives and matching roles, plus an ambient
`primary_domain` / `default-domain`.

**Builders (14)** — html, dirhtml, singlehtml, latex, epub, man, texinfo, text,
xml, gettext, changes, **linkcheck**, **doctest**, **coverage**. The last three
are verification builders and have no counterpart in Notion, Obsidian or Yuque.

**Extensions (19 bundled)** — autodoc, apidoc, autosummary, napoleon,
autosectionlabel, intersphinx, extlinks, graphviz, inheritance_diagram, todo,
ifconfig, duration, viewcode, linkcode, imgconverter, githubpages, math,
coverage, doctest.

## 3. Relations

| Relation | Cardinality | Notes |
|---|---|---|
| toctree **positions** document | 1:1 | unreachable ⟹ diagnostic unless `:orphan:` |
| document **declares** label | 1:N | `:ref:` targets |
| domain **owns** object | 1:N | the type namespace |
| reference **resolves to** target | N:1, **kind-checked** | wrong kind ⟹ failure |
| project **publishes** inventory | 1:1 | `objects.inv` |
| project **consumes** inventory | 1:N | intersphinx mapping |
| doctest block **belongs to** group | N:1 | setup runs first |
| coverage **measures** object | 1:1 | documented or named as missing |

## 4. Where it disagrees with Hermes

| Question | Sphinx | Hermes |
|---|---|---|
| Are references typed? | **yes**, by domain | no — one flat resolver |
| Is ambiguity an error? | **yes** — `:any:` warns on 0 *or >1* | reported at definition, silent at use |
| Are unresolved refs fatal? | **yes**, nitpicky mode | dead links refuse; **fragments unchecked until HW.3.4.3** (now built) |
| Is documentation executed? | **yes** — doctest builder | not yet (HW.9.3.*) |
| Is doc coverage measured? | **yes** | only *formal* coverage |
| Does the build import code? | **yes** — autodoc, coverage | **never** — that would end determinism |

## 5. What the ontology recommends

Take: **typed reference roles** (HW.3.7.1), **ambiguity-as-error** (HW.3.7.2),
**nitpicky with a disclosed `!` opt-out** (HW.3.7.3), **glossary + `:term:`**
(HW.3.7.4), **the reference inventory** (HW.3.8.1–2), **declared navigation with
`:orphan:`** (HW.6.8.1–2), **doctest** (HW.9.3.*), **doc coverage** (HW.9.4.*),
**`literalinclude` with marker slicing** (HW.9.2.1).

Decline: reStructuredText as a source format, the extension API, the
LaTeX/ePub/man/texinfo builders, and — on a *design* ground rather than scope —
**import-based introspection**, because the build must import nothing.

Cross-references: `[[Sphinx — fractal atlas]]` · `[[Sphinx — fractal algebra]]`.

Part of [[Knowledge fractal map]].
