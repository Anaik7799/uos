---
id: hermes-sphinx-fractal-atlas
status: published
type: reference
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Sphinx — fractal atlas

#feature #src-sphinx #area-atlas #cov-analysis

## 1. Static structure

```
Project (conf.py) ──────────────────── S0
  └── toctree ──────────────────────── declared hierarchy
        └── Document ───────────────── S1  :doc:
              ├── Section / label ──── S2  :ref:
              ├── Object (domain) ──── S3  :py:class: :cpp:func: …
              └── Term (glossary) ──── S4  :term:
objects.inv ──────────────────────────  SX  published name → URI
     ▲ consume (intersphinx)      ▼ publish
 other projects                other projects
```

## 2. Control flow — the build is the product

```
sources ──read──▶ environment (cached, incremental)
                       │
                       ├──▶ resolve references ──▶ nitpicky? ──▶ FAIL on unresolved
                       ├──▶ html / dirhtml / singlehtml / text / …
                       ├──▶ linkcheck  ──▶ external URL report
                       ├──▶ doctest    ──▶ RUN the documentation
                       └──▶ coverage   ──▶ what is undocumented
```

This is the diagram no other comparator has. Three of the fourteen builders do
**nothing but verify**, and the environment is incremental with an explicit
dependency relation. Hermes has the differential gate; Sphinx has the
verification *builders*. They are complementary and we should have both.

## 3. Data flow

```
reST / MyST ──parse──▶ docutils doctree ──▶ builder ──▶ output
                            │
                            └── inventory extraction ──▶ objects.inv
```

Canonical form is the **source text**, like Obsidian and like us — so a digest
gate would work here too, and Sphinx instead spends its verification budget on
references and executability.

## 4. The reference-checking ladder

| Check | What it catches | Hermes |
|---|---|---|
| `isPathBrokenLink` (Docusaurus term) / missing `:doc:` | dead document | ✓ site law |
| missing `:ref:` label | dead anchor | ✓ HW.3.4.3 (landed this session) |
| `:term:` not in a glossary | undefined vocabulary | →HW.3.7.4 |
| `:any:` with 0 matches | dead reference | ✓ |
| `:any:` with **>1** match | **ambiguous** reference | ✗ — we report at the definition site only |
| nitpicky | ANY unresolved reference | →HW.3.7.3 |
| unreachable document | not in any toctree | →HW.6.8.2 |
| linkcheck | rotted external URL | →HW.8.2.5 |
| doctest | prose that no longer matches the code | →HW.9.3.1 |
| coverage | code with no prose at all | →HW.9.4.1 |

Reading the column downward is a maturity ladder for our own gate, and the
first two rungs are already ours.

## 5. Atlas verdict

Sphinx is the only comparator that treats a document as **an assertion about a
codebase that can be checked**, which is the same premise as this harness. It
contributes the entire verification family (nitpicky, doctest, coverage,
linkcheck), cross-project references, typed reference namespaces, and declared
navigation with a disclosed orphan opt-out.

Its one importable *prohibition*: the coverage and autodoc builders **import
modules**, so build-time side effects execute. Take the doctest idea, reject
the import-based extraction it usually travels with.

Cross-references: `[[Sphinx — fractal ontology]]` · `[[Sphinx — fractal algebra]]`.

Part of [[Knowledge fractal map]].
