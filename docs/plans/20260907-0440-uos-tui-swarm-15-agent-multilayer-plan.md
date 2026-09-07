# 20260907-0440- uos_tui Swarm Plan: 15 Agents, Multilayer Supervisor, Fast OODA, STPA/FMEA/TPS, Zero-Muda
#fractal-l0 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l8 #zero-muda #tailscale-web #km-triad #uos-tui #swarm #stamp-stpa

- **Plan Identifier**: `PLAN-UOS-TUI-SWARM-001`
- **Timestamp**: `20260907-0440-`
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/plans/20260907-0440-uos-tui-swarm-15-agent-multilayer-plan.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/plans/20260907-0440-uos-tui-swarm-15-agent-multilayer-plan.md)
- **Ledger (machine-readable, progress monitored)**: `apps/uos_tui/swarm/20260907-0440-swarm-ledger.json`
- **Base change**: `vvrtrspvmtqq` (uos_tui v0.1, 116 tests). Integration change: child of base, default workspace. Bookmark on completion: `integration/uos-tui-swarm`.
- **Transclusions**: `[[zk:20260906-2150-adr-061-uos-tui-gleam-library-textual-reference]]` `[[wiki:20260906-2150-uos-fractal-textual-ontology-wiki]]` `[[wiki:20260906-1730-uos-omni-fractal-matrix-and-17-aspect-wiki]]`

## Comprehensive Verification Checklist (SC-CHECKLIST-001)
<details><summary>18 checkpoints (plan-time status)</summary>

CHK-01 PASS (prefix) · CHK-02 PASS (link) · CHK-03 PASS (tags) · CHK-04 PASS (transclusions) · CHK-05 PASS (no barred deps permitted to workers) · CHK-06 PASS (only `crypto:strong_rand_bytes` external allowed, W06) · CHK-07 PASS (serial unchanged) · CHK-08 PLANNED · CHK-09 NOT MEASURED · CHK-10 PLANNED (each slice ≥1 property + ≥1 fuzz/chaos test) · CHK-11 N/A · CHK-12 PASS (driver child_spec exists) · CHK-13/14/15 DECLARED · CHK-16 PLANNED (W06) · CHK-17 PENDING · CHK-18 PASS (jj workspaces, zero git)
</details>

## 1. Thinking (OODA at L0)

**Observe.** uos_tui v0.1 passes 116 tests but has open gaps: no command palette, no markdown, no frame diffing, no trace ids, no STPA/FMEA artefacts, no TPS flow control, no dashboard, no feature sheet. Eleven of these are independent modules with disjoint file ownership.
**Orient.** Disjoint ownership means the work parallelises without merge conflicts if every worker only creates its own files. Gleam is niche, so code workers need a mid-tier model; verification and documentation are mechanical and go to the cheapest tier. Jujutsu sibling workspaces give each worker its own build directory and its own commit, and the shared `.jj` store lets me integrate with `jj squash --from <ws>@ --into @` without rewriting the base.
**Decide.** 15 agents: 10 Sonnet code workers + 1 Haiku doc worker (L2), 4 Haiku group verifiers (L3), Fable as L0 supervisor and L1 integrator. No retries inside the swarm; a red verdict is a jidoka stop and the supervisor repairs or drops the slice.
**Act.** Launch one Workflow: four groups flow through worker → verifier as a pipeline (no barrier between groups). Integrate green slices, wire the entry point, generate documents from Gleam, publish the dashboard, journal.

## 2. Multilayer supervision

| Layer | Who | Responsibility | Model | Why this tier |
|---|---|---|---|---|
| L0 program | Claude Fable (this session) | scope, OODA, jidoka decisions, admission | fable | judgement, integration risk |
| L1 integrator | same session | jj squash, wiring, doc generation, artifact | fable | needs full context |
| L2 slice workers | W01–W10 | one Gleam module + tests each | sonnet, medium | Gleam competence at mid cost |
| L2 doc worker | W11 | Textual widget-gallery parity wiki | haiku, low | mechanical, web-sourced |
| L3 verifiers | V1–V4 | format, warnings, tests, forbidden patterns, ownership | haiku, low | command-running, no design |

## 3. Tasks and jobs (WBS)

| ID | Slice | Owned files | Min tests | Group |
|---|---|---|---|---|
| W01 | swarm ledger decode, KPIs, dashboard screen | swarm.gleam | 10 | G1 |
| W02 | feature sheet generator (from code) | features.gleam | 8 | G1 |
| W03 | command palette fuzzy search | palette.gleam | 10 | G1 |
| W04 | markdown renderer to strips | markdown.gleam | 10 | G2 |
| W05 | dirty-row frame diff (zero-muda repaint) | diff.gleam | 10 | G2 |
| W06 | C3I telemetry trace/span, ISO8601 µs Z | telemetry.gleam | 10 | G2 |
| W07 | STPA + FMEA models with validation | stpa.gleam, fmea.gleam | 12 | G3 |
| W08 | fast OODA loop controller, Lyapunov trend | ooda.gleam | 10 | G3 |
| W09 | TPS kanban, takt, WIP, jidoka, andon, 7 muda | tps.gleam | 10 | G3 |
| W10 | HTML dashboard builder | html.gleam | 8 | G4 |
| W11 | Textual widget-gallery parity wiki | docs/wiki/… | 0 | G4 |
| V1–V4 | verify G1–G4 | none | — | — |

## 4. Workflow

```text
 L0 Fable ──plan──▶ ledger.json ──▶ Workflow(15 agents)
   G1 [W01 W02 W03] ─┐        G2 [W04 W05 W06] ─┐        G3 [W07 W08 W09] ─┐        G4 [W10 W11] ─┐
        ▼            │             ▼             │             ▼             │           ▼         │
       V1 ◀──────────┘            V2 ◀───────────┘            V3 ◀───────────┘          V4 ◀───────┘
        └────────────── verdicts ──────────────▶ L1 integrate: jj squash green slices → gleam test → wire → generate docs → dashboard → journal
```

## 5. STPA for the swarm itself (control structure: L0 → L2/L3 → jj store)

| UCA | Type | Control action | Context | Hazard | Constraint / enforcement |
|---|---|---|---|---|---|
| UCA-SW-1 | provided unsafe | worker writes file | outside owned list | overwrites shared module | verifier ownership check via `jj diff --summary` (harness check) |
| UCA-SW-2 | not provided | verifier runs tests | skipped or parsed wrongly | false green | verifier must quote the "N passed" line (harness check) |
| UCA-SW-3 | wrong timing | integrator squashes | before verdict | unverified code in @ | integration only after verdict PASS (process rule) |
| UCA-SW-4 | stopped too soon | worker returns | tests red | broken slice reported done | schema requires test summary; V re-runs (harness check) |
| UCA-SW-5 | provided unsafe | base commit rewritten | workers active | stale workspaces | L0 never edits base during swarm (process rule) |

## 6. FMEA (top rows; full table generated by W07 after integration)

| Item | Mode | S | O | D | RPN | Mitigation |
|---|---|---|---|---|---|---|
| verifier | false green | 9 | 3 | 4 | 108 | quote test line; integrator re-runs full suite |
| worker | modifies shared module | 8 | 3 | 2 | 48 | jj diff summary ownership check |
| integration | two slices add same symbol in entry file | 5 | 4 | 2 | 40 | workers never touch uos_tui.gleam; L1 wires |
| token budget | worker explores tree | 3 | 6 | 3 | 54 | API sheet file + "do not explore" rule |
| jj | stale workspace after squash | 2 | 9 | 1 | 18 | workspaces forgotten after integration |

## 7. TPS

Takt: 12 min per slice target (11 slices, ~2h wall-clock budget incl. integration). WIP limit 11 (one slice per worker, no multitasking). Pull: verifier pulls a group only when all its workers returned. Jidoka: any red verdict stops that slice's line; andon turns yellow; two reds turn andon red and the supervisor re-plans. Poka-yoke: schema-forced outputs, ownership lists, forbidden-pattern grep. 7 muda mapped: overproduction (no docs by workers except W11), waiting (pipeline, no barrier across groups), transport (workers read one API sheet file), overprocessing (min-test floors, not maxima), inventory (no half-done slices integrated), motion (absolute paths given), defects (verifiers + full-suite re-run).

## 8. KPIs (computed into the ledger and the dashboard)

completion % · pass rate · first-pass yield · tests added · LOC added · tokens out per slice · cycle time per slice vs takt · WIP · jidoka stops · andon state · aspects Pass/Declared/Fail after integration · frame µs.

## 9. Addendum (20260907-0447-): shared message board over Zenoh with full semantic tracking

**Observed transport state (fail-closed evidence, 2026-09-07T04:47Z)**: cockpit `/api/zenoh/health` reports `connected:false, routers:0`; no `zenohd` on nas-1; port 8000 is a printer service, not the Zenoh REST plugin; vm-1:8000 unreachable. Cepaf reaches Zenoh only through the Rust NIF in `cepaf_gleam_ffi` (`zenoh_open/put/get/subscribe`), which uos_tui must not link (0-NIF invariant).

**Decision**: module `uos_tui/board` (built by L1 after W06 telemetry and W07 STPA integrate, because every message carries their ids).

1. **Message envelope (every field mandatory, all semantic detail tracked)**: `id` (ULID-style: µs timestamp + 80 random bits), `trace_id`/`span_id`/`parent_span_id` (W3C, from `telemetry`), `ts_us` and `ts_iso` (µs UTC `Z`), `swarm`, `from` (agent id + layer + model), `to` (agent id, group, or `broadcast`), `kind` ∈ {Plan, Dispatch, Claim, Progress, Question, Answer, Report, Verdict, Andon, Jidoka, Integrate, Heartbeat, Intent}, `key_expr` (Zenoh key), `payload` (typed JSON), `semantics` = {`ontology_concepts` (names from `ontology.graph()`), `aspects` (numbers 1..17), `control_actions` (ids from `stpa.model()`), `muda` (7-waste tags), `fractal_layer`}, `causality` = {`in_reply_to`, `caused_by` (message ids)}, `digest` (SHA-256 of canonical JSON via `crypto:hash`, pure Erlang), `delivery` = {`transport`, `status` ∈ Delivered|Queued|Unavailable(reason), `attempts`}.
2. **Key expressions (Zenoh)**: `c3i/a2a/uos-tui-swarm/<from>/<kind>` for directed/broadcast messages, mirroring cepaf's `c3i/a2a/` plane and `c3i/a2a/broadcast`; queries use `c3i/a2a/uos-tui-swarm/**`.
3. **Transports**: `ZenohRest(base_url)` (standard Zenoh REST plugin: `PUT <base>/<key>` JSON, `GET <base>/<key>/**`), `FileLedger(path)` append-only JSONL (always on; the source of truth for tracking), `Memory` (tests). A message is `Delivered` only when the REST put returns 2xx; otherwise `Unavailable(reason)` with the ledger still written. No transport is ever simulated.
4. **Tracking guarantees**: append-only, digest-chained (`prev_digest` field), replayable into the swarm dashboard (`board.timeline`, `board.by_agent`, `board.by_kind`), validated by `board.validate` (referential: reply targets exist, ids unique, chain intact, every semantic ref resolves against ontology/aspects/STPA).
5. **Retroactive ingestion for this run**: the Workflow journal (`journal.jsonl`) is ingested as `Dispatch`/`Report`/`Verdict` messages so the 15-agent run is fully tracked even though the agents were launched before the board existed.
6. **CLI**: `gleam run -- board post|timeline|validate|ingest`.
