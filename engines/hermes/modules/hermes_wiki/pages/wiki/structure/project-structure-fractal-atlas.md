---
id: hermes-project-structure-fractal-atlas
status: published
type: reference
ktype: moc
maturity: incubating
domain: formal_verification
topics: [structure, workspace, atlas, flows]
created: 2026-08-09
last_verified: 2026-08-12
verified_by: agent
next_review: 2026-09-09
---
# Project structure — fractal atlas

The workspace on one map: the static tree, the flows, and where every
gate stands. Entities in [[Project structure — fractal ontology]]; laws in
[[Project structure — fractal algebra]].

## 1. The static map

```
/                         dune-project (W0) · dune = the scan policy (WX)
├── modules/              PRODUCTION — 19 component directories, 35 dune files
│   ├── hermes_wiki/      wiki/ZK/KM; source closure includes hermes_sysml
│   │   │                 and hermes_fpp_authority (see §3 and SW6)
│   │   ├── src/          engine·control·graph·km·search·reconcile·register·fpp·tools·serve
│   │   ├── test/         the wiki battery      baseline/  ALL the pins
│   │   ├── pages/        the corpus            import/    mirrors, manifested
│   ├── hermes_harness/   evidence/parity plane (consumes the wiki from above)
│   ├── hermes_ops/       the offload layer (R22) — ops_main.exe, the gate set
│   ├── hermes_ops_dashboard/  run-plane projections: algebra·atlas·mbse·formal
│   ├── swarm/            SOP execution engine (owned by a parallel session)
│   ├── hermes_agent_loop/     candidate runtime — the one promoted family
│   ├── hermes_dependability/  dependability algebra + SQLite lifecycle solver
│   ├── hermes_fpp_authority/  the neutral FPP base-id window authority
│   ├── hermes_vision/    capture·stream·infer·browser·telemetry·safety
│   ├── hermes_sysml/     SysML v2·OML semantics and formal topology checks
│   ├── hermes_toolchain/ toolchain_check.exe — the switch gate (R20)
│   ├── system_engg/      authority·licensing·locks·exact-head·agent sync
│   ├── sa_plan/          durable plan/job/schedule/store control plane
│   ├── hermes_server/ · fetch_cowboy/ · hermes_harness_stubber/
│   └── hermes_cli/ · gateway/ · hermes_sqlite/  EMPTY reservations
├── projects/             INCUBATION: ocaml_agent/ · satellites/vision/
├── docs/hermes/          RECORD: rules·plans·specs·maps·zk·append-only journal
├── state/                RUNTIME: sqlite·otel·dashboard·site·tmp·vision
├── zigvm_legacy/         PARKED: mapped ZigVM history
├── external · third_party · vendor   VENDORED (data-only)
├── generated/            DERIVED: Aeon·agent·Lean·MBSE·Quint·Rocq projections
├── rust · scripts · ui_web · webedit · tools · providers · _gospel
│                         AUXILIARY DATA-ONLY: explicit SW1/SW4 residual
└── .claude · .agents · .codex · .gemini   WX agent policy/projections
```

## 2. Where the gates stand

```
scan policy (dune, WX)      ──▶ what CAN build        the outermost gate
toolchain_check (R20)       ──▶ which switch MAY build  derived dependencies
ops verify profile          ──▶ declared suites run   skips disclosed, never green
render differential        ──▶ what pinned corpus IS byte-equality over 240 pages
ratchet (29 gauges)        ──▶ which counts may move monotone down only
guarded commands           ──▶ who may WRITE         PIN_BASELINE · APPLY_BATCH
scoped ledgers             ──▶ register/import/legacy totality inside their domains
```

## 3. The flows

- **Content**: `pages/` → model → render → pinned digest → site (`state/`).
- **Evidence**: probe → register row → dashboard KPI → OTel record.
- **Dependency guard**: `hermes_harness ─▶ hermes_wiki` and never back —
  `test_hermes_wiki` rejects `hermes_harness_*` names in wiki Dune files.
  That is a narrower property than standalone liftability. The wiki does
  **not** depend only on itself and vendored externals:
  `src/mbse` requires `hermes_sysml` and `src/fpp` requires
  `hermes_fpp_window_authority`. Both are `src` edges, not test edges, so
  lifting the wiki out takes those two components with it. The guard law
  greps for `hermes_harness_*` and cannot see either.
- **Granularity**: the dependency unit is the **library**, not the
  directory. `hermes_ops` and `hermes_ops_dashboard` each depend on the
  other as directories while the library graph stays acyclic — dune
  proves it, since it rejects a library cycle and the workspace builds. A
  directory-level reading reports cycles that do not exist.
- **Promotion**: `projects/X` graduates to `modules/X` only through the
  algebra's guarded `promote` (battery + rows + window + shared logging).
- **Parking**: anything leaves the build only through `park` — a map entry
  first, the move second (the undo-record discipline).
- **Projection**: generated models, rendered site, dashboards and native
  agent files derive from their typed or tracked authorities; they are not
  independent descriptions of the tree.

Part of [[Knowledge fractal map]].
