---
id: c6afdea4-a56c-4e01-f4d1-bc3d2ee33910
title: "Sa-plan C3I observability, differential parity, and admission"
type: zettel
status: evergreen
created: 20260804-131604
topics: [sa-plan, c3i, oban, temporal, observability, safety, performance]
links: ["[[20260804-125557-sa-plan-pipeline-observability]]", "[[2026-08-04-0936-infranodus-fractal-closure]]", "[[SA_PLAN_CLI_DOMAIN]]"]
verified_by: agent
---

# Sa-plan C3I observability, differential parity, and admission

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260804-131604-sa-plan-c3i-admission.md](http://nas-1.tail55d152.ts.net:4100/zk/20260804-131604-sa-plan-c3i-admission.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


Sa-plan control truth is the durable OCaml Store. Leases are at-least-once;
stable activity keys make effects idempotent. Bonsai, TUI, journals, wiki/ZK,
timing headers, and C3I corpus JSON are read-only observations.

The C3I normal form verifies plan/job states, ordered workflow history, retry
timing, activity idempotency, and job terminal outcomes. Retry delay is
`min(3600s, 15s * 2^attempt)`. The external Rust daemon's canonical-cwd,
read-only status is live after the C3I project's 13:15 repair (v22.5.0, 3,174
completed tasks, 7 ms internal). A mutating isolated runtime differential and
OCaml workflow cancellation remain `Unavailable_observed`.

The source-map journal also exposes a control hazard: the binary resolves
`Planning.db` relative to its working directory. A noncanonical direct launch
observed a different 291-task database, while the wrapper contract changes to
`sub-projects/c3i/` and observes 3,174 tasks. Runtime verification therefore
must bind and report the canonical working directory.

Pipeline benchmark: Sa-plan snapshot 2–3 ms in-process; durable completion /
selection transactions 15–19 ms; live Bonsai 535–662 ms dominated by model
loading; cold journal publication 20–23 s dominated by `Docs_wiki.build`'s
`O(notes² + edges)` ZK relation scan; warm publication 65–87 ms.

Recommended improvements: content-addressed per-note relation indexes,
affected-neighbor incremental closure, a lightweight Bonsai operations model,
bounded correlated OTEL logs, and a persistent compiled Sa-plan service to
avoid launcher overhead. [[20260804-125557-sa-plan-pipeline-observability]]
contains the stage-level evidence.

---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
