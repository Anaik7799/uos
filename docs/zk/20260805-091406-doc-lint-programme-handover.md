---
id: 6d41f8a3-9c27-4e15-b8d0-3a7e21c95f04
status: draft
last_verified: 2026-08-05
verified_by: agent
---
# Document-lint programme — record and handover

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260805-091406-doc-lint-programme-handover.md](http://nas-1.tail55d152.ts.net:4100/zk/20260805-091406-doc-lint-programme-handover.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


20260805-091406. Commits `84fb39b` → `541338a` → `f3d88c3` → `41cec23` → `350a629` → `628c9e9` → `8caac4a` → `e61e249` → `fd8b2c1` → `dfc0a2e`.

**What exists.** `harness/doc_lint.ml` is a lint algebra: a document is `(path, kind, bytes)`, a rule is a named TOTAL function `doc → findings`, the linter is the fold of a registry over a corpus in a monoid. Pluggable (a rule is a value appended to `registry`; the engine is never edited), total (a raising rule becomes a finding against itself), deterministic, measured. 15 rules over five artifact kinds (Markdown, HTML, JSON, Zig, OCaml), 1534 files / 426 kloc / 41 MiB linted on every gate run at ~98 MiB/s.

**Benchmarked in strict mode** against the ranked field: W3C Nu `vnu` 26.8.4 (the conformance reference), markdownlint-cli2 0.18.1, remark-lint 15.0.1, html-validate 10.17.0, HTMLHint 1.9.2 — all installed outside the repo for measurement only. `vnu` with nothing filtered returns ZERO messages on the journals this session authored. Honest boundary recorded: vnu catches missing `<title>`, heading-level skips, broken data URIs, missing `lang`, doctype position, CSS validity and element nesting that this linter does not, so `lint check: ok` is a NARROW green. Conversely a remote runtime `<script src=https://>` is valid HTML that no conformance checker flags, and this linter is the only thing enforcing the journal contract's no-remote-runtime clause.

**Governance.** `SAFETY_ANALYSIS.md` CTRL-DOC-LINT (four hazards, six constraints, FMEA, priority argument); `SC-LINT-RATCHET` armed in the Zero-Trust `verify_cycle` path rejects a cycle editing the lint ceiling without a visible `ratchet:` statement; `docs/design/lint-baseline.txt` is monotone non-increasing at `errors = 0, warnings = 60`. 49 gate-wired laws: BDD per rule, registry/monoid/determinism properties, 400-document seeded fuzz for totality, and `PARALLEL-EQUALS-SEQUENTIAL` at 1/4/8 domains.

**The performance finding worth keeping.** Parallelism bought 1.17×; removing one allocation bought 12× (2414 ms → 162 ms, 15 → 94 MiB/s). The scanners called `String.sub` at every byte position. It presented exactly as a parallelism plateau and the Amdahl reasoning was correct as far as it went — it was not the binding constraint. Measure the constraint before optimising the architecture.

**Ten defects found in the programme's own work**, every one by running over the real corpus or by the control catching its author — including a second unknown corruption of `FIGMA_FRACTAL_STPA_ENVELOPE.md` that had been live on the wiki, and four instances of the self-reference hazard (a registry naming an index it does not define; a review note quoting live section numbers; a rule catalogue containing the pattern it forbids; a journal embedding the rule literals, fixed by a markup-only view rather than a suppression).

**Trigger tests recorded, not implemented.** Stan DOES NOT FIRE — lint counts are exact, so a posterior would put a credible interval around a known number. Ruliology PARTIALLY FIRES, deferred with a named trigger: `ISOLATION` holds by construction, so if it is ever relaxed the rule space must be explored before the relaxation is admitted.

**HANDOVER — open ask, not started:** dashboard, metrics, KPIs, OTEL, diagrams and analytics for the lint pipeline. Everything needed is already computed each run and simply not exported (per-stage timings, per-rule cost, `Doc_lint.kpis`, severity-ranked findings, `rule_catalogue`). Suggested shape and gotchas are in the journal §6: a separate projection module, OTEL spans in Unix nanoseconds, a self-contained HTML dashboard with inline SVG that must pass this repo's own linter, and a report-only observation plane that never mints gate state.

Journal: http://vm-1.tail55d152.ts.net:8092/doc-lint-programme-handover.html (sha256 e5904fc95255649e604b7f719a450b2b26095489bc783ab143a6fffb62b48a1e, route byte-verified, all artifacts embedded). Relates: [[zk--20260805-065319-design-onboarding-and-functional-domain-artifacts]].

#lint #algebra #benchmark #stpa #parallelism #handover #journal

---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
