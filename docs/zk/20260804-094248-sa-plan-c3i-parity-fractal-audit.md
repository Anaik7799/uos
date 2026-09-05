---
id: 9868471b-1e36-a29c-3360-2ac0ea4cb5a1
title: "Sa-plan C3I/Rust parity fractal audit"
type: moc
status: incubating
domain: [sa_plan, c3i, ocaml, distributed_systems]
topics: [oban, temporal, planning, jobs, workflows, ui, stpa, fmea]
tailscale_fqdn: "http://vm-1.tail55d152.ts.net:8092/20260804-093039-approach-b-observability-journal.html"
created: 2026-08-04
observed_at: 20260804-094248
links: ["[[20260804-093039-approach-b-observability-journal]]", "[[FRACTAL_ONTOLOGY]]", "[[ONTOLOGY]]"]
verified_by: agent
---

# Sa-plan C3I/Rust parity fractal audit

- **Tailscale Web FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/zk/20260804-094248-sa-plan-c3i-parity-fractal-audit.md](http://nas-1.tail55d152.ts.net:4100/zk/20260804-094248-sa-plan-c3i-parity-fractal-audit.md)
- **Fractal Coordinates**: `#fractal-l0` through `#fractal-l9`
- **Knowledge Tags**: `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda`
- **Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`


## Audit scope

This audit covers all newly added closure work and the requested OCaml parity
with C3I/Rust planning, job management, Oban and Temporal systems, including
the UI and observability surfaces.

## Evidence baseline

* OODA observation: current harness frontier is `boundary/check-docs/check-fixtures/run-suite`; next unrelated slice is `http-laneD-envelope-evidence`.
* Safety: 52 UCAs and 48 constraints tracked; 36 enforced, 2 planned, 10 process.
* Time: host NTP synchronized; Claude context sync is stale and therefore not trusted.
* Approach B metric algebra: focused OCaml laws GREEN.
* Sa-plan Store: registration, dependency order, compare-and-set claim,
  restart durability, lease reclaim, cycle rejection and activity idempotence GREEN.
* Durable plan: `infranodus-fractal-closure-20260804-0936`, 18 tasks; Task 0
  completed through the OCaml Sa-plan runner, 2 tasks ready.

## Fractal matrix

| Layer | Audited surface | Terminal observation |
|---|---|---|
| L0 boundary | OCaml-only authorship, DB law, Tailscale publication | Verified for changed slice |
| L1 artifact | plans, skills, rules, agents, journal, ontology, ZK | Verified as synchronized projections; Sa-plan is authority |
| L2 subsystem | Sa-plan Store, Oban, Temporal, UI, C3I bridge | Store verified; legacy Oban/Temporal are `Unavailable_observed` for durable parity |
| L3 module | Store, metric algebra, management, queue/workflow modules | Store/metrics tested; legacy simulations require Tasks 12–16 |
| L4 feature | plan/job/workflow/UI operations | Terminalized by Tasks 12–17; no fabricated feature parity |
| L5 representation | initial model/final SQLite/event history | Store final interpretation verified for current scope; C3I differential pending |
| L6 operation | register, claim, complete, retry, signal, timer | register/claim/complete/idempotency verified; retry/signal/timer parity pending |
| L7 generator | seeded laws, reference corpus, UI journeys | current focused generators verified; C3I corpus pending |
| L8 mutation | dependency guard, double claim, parity mutants | two Sa-plan mutants covered; parity mutant campaign pending |
| L9 verification | canonical gate, differential parity, Playwright | focused gates green; full parity evidence pending |
| L10 governance | STAMP/STPA/FMEA, Rete admission, agent control | safety baseline valid; parity controls added to Task 17 |

## Dependency and utility balance

Safety/truthfulness and durable task authority dominate utility. The highest
centrality path is `Task 12 -> Task 13/14 -> Task 15/16 -> Task 17`; profile and
UI decoration cannot outrank durable job/workflow semantics. Parallel work is
allowed only between independent Task 13 and Task 14 after Task 12 is green.

## STAMP/STPA/FMEA summary

* Controller: OCaml Sa-plan runner; controlled process: durable plan/job/workflow store.
* Unsafe actions: claim without dependency readiness, duplicate claim, lost
  lease, replayed side effect, missing workflow event, UI write-through, and
  stale agent-plan state.
* Controls: transaction/lease predicates, unique activity keys, event append
  laws, read-only UI, typed runner-only mutation and exact-HEAD gate.
* Residuals: C3I/Rust reference access and full Oban/Temporal surface are not
  yet independently observed; they remain explicitly tracked, not complete.

## Terminal-state rule

There are no unclassified findings. Verified findings have readable evidence;
external/unavailable parity is named with a reopen observation; implementation
work is represented as Sa-plan tasks and cannot be closed by this document.

## Next Sa-plan actions

Claim `task-1` and `task-12` only through the OCaml runner. Complete each only
after its focused laws and evidence pass. Never edit a Markdown checkbox as a
substitute for a Store transition.

---

### Navigation & Knowledge Triad
- **Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)
- **Hermes Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki)
- **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md](http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-1845-uos-wiki-zk-km-synthesis-review-tome.md)
