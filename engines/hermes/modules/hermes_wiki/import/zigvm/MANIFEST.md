# zigvm import manifest — 2026-08-09

Reference artifacts imported VERBATIM from /home/an/dev/ver/zigvm
(source state: 3cf87fedbc51e37c64eee057c30a553f9d346170) to accelerate the unified wiki/ZK build-out.

DISPOSITION (R9/R14): mirror sources, tracked for availability and diff,
NOT wired into the dune build — each piece enters the build only through
its feature-register row, ported and law-tested. This directory is outside
the corpus roots, so nothing here is a wiki page.

| Dir | Contents | Count |
|---|---|---|
| skills/ | wiki-design, zk-knowledge-base, tyxml-conversion, docs-design, infranodus-design-superset | 5 skills |
| design/ | tokens.css, tokens.json, DESIGN.md, DOMAIN_GLOSSARY.md, DOMAIN_MODEL.md, COPY_DECK.md | 6 files |
| code/core/ | docs_wiki(+laws), markdown_ast(+laws,mli), typed_html, route_algebra, figma_design(+mli), dump_figma_design | 10 files |
| code/graph/ | the graph_* stack | 18 files |
| code/wiki/ | the wiki_* checker fleet | 11 files |
| code/zk/ | the zk_* enforcer/prover fleet | 29 files |
| templates/ | zk_template_variable_substitutor | 1 |
| rules/ | full-symbiosis.md, zigvm CLAUDE.md | 2 |

Already imported earlier as CORPUS PAGES (not duplicated here):
WIKI_PIPELINE/TABLE/HTML/ROUTE/WEB_ALGEBRA docs, the 146-document
features/bonsai/journal collation (hermes_wiki/pages/wiki/).

## Tranche 2 — 2026-08-09, the root-file mapping sweep

Provenance: the repo root's untracked zigvm-era workspace (same origin as
tranche 1). Credential-scanned; one false positive inspected and cleared
(`journal_bundle`'s own `Secret` privacy *classification* — the type whose
job is to REJECT secret artifacts). Disposition unchanged: **mirror
sources** (R14/R9) — outside the dune build, entering the system only
through feature-register rows.

| Where | What | Count |
|---|---|---|
| code/core/ | doc_lint, gen_markdown_baseline, json_embed(+laws), route_laws, render_markdown_file, note_ref; tests for figma_design, route_algebra, typed_html | +10 |
| code/journal/ | the journal_bundle system: bundle, digest, io, telemetry, transaction, dashboard/html playwright checks, markdown→html, playwright contract, render_journal_html; its seven test suites | 24 |
| code/km-profiles/ | logseq_profile(+mli, test, renderer); notion.ml — Notion's feature model as OCaml with a pure Model→View projection | 5 |
| code/infranodus/ | the InfraNodus stack: acquisition, artifacts, feature, fractal-closure plan, full-UI playwright, host adapter, scenario; five test suites (test_infranodus_evidence is self-contained — no subject module exists) | 16 |
| code/playwright/ | playwright_authority, playwright_controller (+test), playwright_ontology, playwright_source_ontology | 5 |
| code/graph/ | six test suites for the already-imported graph stack | +6 |
| code/wiki/ | test_wiki_selfcheck_parallel; test_wiki_shell (self-contained — no wiki_shell.ml exists at root) | +2 |

68 files (42 modules + 26 test/law mirrors — tests are the law statements,
half the value of a mirror source); the code tree now holds 136. The
complete classification of all 384 root OCaml files (including the 248
deliberately NOT imported) is `docs/hermes/root-ocaml-file-map.md`.
