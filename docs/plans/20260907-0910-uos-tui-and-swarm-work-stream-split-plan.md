# 20260907-0910- Work-stream split: TUI library vs swarm / hive mind
#fractal-l0 #fractal-l2 #fractal-l4 #fractal-l5 #zero-muda #tailscale-web #km-triad #uos-tui #swarm #jujutsu

- **Plan Identifier**: `PLAN-UOS-TUI-SWARM-SPLIT-001`
- **Timestamp**: `20260907-0910-`
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/plans/20260907-0910-uos-tui-and-swarm-work-stream-split-plan.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/plans/20260907-0910-uos-tui-and-swarm-work-stream-split-plan.md)
- **Operator directive (verbatim)**: "split and tui and swarm work into separate work streams"
- **Transclusions**: `[[zk:20260906-2150-adr-061-uos-tui-gleam-library-textual-reference]]` `[[zk:20260907-0537-adr-062-uos-tui-swarm-hive-mind-message-board-coordination-acl-and-zenoh-infra]]` `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`
- **Status**: executed 20260907-0950; see ADR-063 and `docs/journal/20260907-0950-uos-tui-swarm-work-stream-split-journal.md` for full execution record.

## Comprehensive Verification Checklist (SC-CHECKLIST-001)
<details><summary>18 checkpoints (plan-time status)</summary>
CHK-01 PASS (prefix) · CHK-02 PASS (link) · CHK-03 PASS (tags) · CHK-04 PASS (transclusions) · CHK-05 PASS (no new deps) · CHK-06 PASS (no NIF) · CHK-07..CHK-11 DECLARED (unchanged by a move) · CHK-12 PASS (Gleam/OTP only) · CHK-13..CHK-15 DECLARED · CHK-16 PASS (telemetry ids stay in the library) · CHK-17 DECLARED (tri-sovereign review of the split pending) · CHK-18 PASS (jj only; no git)
</details>

## 1. Thinking (OODA at L0)
**Observe.** `apps/uos_tui` holds two things with different cadences and reviewers: a pure TUI library (Textual-referenced widgets, layout, rendering, aspects, F´ dictionary) and a swarm/hive-mind application (board, coordination, manager, ACL, holarchy, agent kernel, audits) that merely uses the library. One package, one CLI and one jj change couple their reviews, tests and admission.
**Orient.** The import graph (computed from `import uos_tui/...` lines) is already almost layered: no swarm module is imported by a TUI module except one violation, `features` → `cockpit` (the feature sheet instantiates the cockpit to count screens). Tests are likewise separable; four test modules (`aspects_test`, `cockpit_test`, `manager_test`, `perf_test`) use the cockpit and belong to the swarm side.
**Decide.** Two packages, two bookmarks, two sibling workspaces, one dependency direction (swarm → tui). The TUI stream keeps the library name `uos_tui`; the swarm stream becomes `apps/uos_swarm` with its own CLI. Docs, generated artefacts and the swarm ledger move with the swarm stream; ADR-061 stays with the TUI stream, ADR-062 with the swarm stream.
**Act.** Execute after the mainline sync lands: move files with `jj file move`-equivalent renames in the working copy, fix the one boundary violation, split the change by path with `jj split`, set bookmarks, add workspaces, run both suites, regenerate artefacts, journal.

## 2. Module allocation (from the dependency graph, 2026-09-07)
| Stream | Package | Modules |
|---|---|---|
| TUI library | `apps/uos_tui` | geometry, style, segment, frame, layout, event, widget, render, app, headless, live, aspects, fprime, ontology, palette, markdown, diff, html, telemetry, features (after the fix below) |
| Swarm / hive mind | `apps/uos_swarm` | swarm, board, coord, manager, acl, holon, agent_runtime, system_audit, stpa, fmea, ooda, tps, cockpit, openrouter_worker (+ session_sync* when its owner agrees) |

Boundary fix: `features.gleam` must stop importing `cockpit`; the screen count it needs becomes a parameter (`features.sheet(screens: List(String))`) supplied by the swarm CLI, or the feature sheet moves to the swarm package. The first keeps the library self-describing and is preferred.

Dependency direction after the split: `uos_swarm` depends on `uos_tui` by path (`uos_tui = { path = "../uos_tui" }`); `uos_tui` depends on nothing in `apps/`.

## 3. CLI, FFI and tests
| Piece | TUI stream | Swarm stream |
|---|---|---|
| CLI entry | `uos_tui.gleam`: snapshot, dictionary, features, features-json, lifecycle demos | `uos_swarm.gleam`: swarm, swarm-tui, tps-demo, dashboard, board *, audit-system, manager-*, holon*, lexicon, hive, controls, lifecycle-machine, acl *, stpa, fmea |
| FFI | `uos_tui_ffi.erl`: raw mode, size, read/write, clocks, file read | `uos_swarm_ffi.erl`: ets, httpc, hmac/sha256, board key, list_dir; `uos_openrouter_ffi.erl` |
| Tests | 18 library test modules | 14 swarm test modules (incl. aspects_test and cockpit_test, which audit the cockpit) |
| Artefacts | none | `swarm/` ledger, board JSONL, ACL files; `generated/` audit, KPIs, hive, controls, lexicon, grammar |

## 4. Jujutsu work streams
| Stream | Bookmark | Workspace | Base |
|---|---|---|---|
| TUI library | `integration/uos-tui` | `.uos-workspaces/tui-stream` | the post-sync mainline |
| Swarm / hive mind | `integration/uos-swarm` | `.uos-workspaces/swarm-stream` | child of `integration/uos-tui` |

Rules: the TUI stream never imports from the swarm stream; the swarm stream integrates the TUI stream by rebasing onto it; integration gates stay serialized (one integrator at a time, announced on the board); `main` moves only by the mainline integrator.

## 5. Execution steps (after "mainline final")
1. Announce the split on the board (Plan, Dispatch) and claim `task:split` with a lease.
2. Create `apps/uos_swarm` (gleam.toml with the path dependency), move the swarm modules, tests, FFI and artefacts; rename module paths `uos_tui/<m>` → `uos_swarm/<m>` for the moved modules; fix `features` → `cockpit`.
3. Build and test both packages (0 warnings each); regenerate the swarm artefacts from the new CLI; re-run `audit-system`.
4. `jj split -r @ apps/uos_tui docs/design/*tui*` to separate the TUI-side change from the swarm-side change; describe both; `jj bookmark set integration/uos-tui` and `integration/uos-swarm`; `jj workspace add` for each stream and rebase the workspace changes onto their bases (lesson: `jj workspace add` parents on @'s parent).
5. Update ADR-061/ADR-062 consequences, apps/README, the hive-mind wiki paths, the pipeline script, and write the 13-section journal for the split.
6. Post Integrate and an Andon on the board; request tri-sovereign review of the boundary (Antigravity, Codex).

## 6. Gates
- G1: no `import uos_swarm/...` in `apps/uos_tui`; `gleam build` of `uos_tui` alone succeeds.
- G2: both suites green with 0 warnings; test counts recorded per stream.
- G3: the regenerated system audit is not worse than 56 / 78 / 2 and the board validates.
- G4: journal, ADR consequences and README updated; bookmarks and workspaces listed in the journal.

## 7. Execution Record

**Executed**: 20260907-0950- by Fable (design authority) + Sonnet W-A (352,872 tokens) + Sonnet W-B (308,739 tokens) in parallel sibling workspaces.

**Gate Results**:
- **G1 PASS**: No `import uos_swarm/...` in `apps/uos_tui`; boundary grep empty; `gleam build` of `uos_tui` alone succeeds.
- **G2 PASS**: uos_tui 198 tests (18 test modules), uos_swarm 271 tests (14 test modules), total 469; both build 0 warnings.
- **G3 PASS**: System audit PASS 56 · DECLARED 78 · FAIL 2 (honest checklist evaluations); board validates at 187 messages; admissible=false pending CHK-09 math gates and tri-sovereign review.
- **G4 IN PROGRESS**: Journal created; ADR-063 created; README.md work streams section added; plan updated; MOC updated with ADR-063 line.

**Change IDs**:
- **T** (integration/uos-tui): `tmwpokqm` — TUI library modules + design docs.
- **S** (integration/uos-swarm): `wyowkrpw` (child of T) — Swarm modules + artefacts + tests.
- **main advance**: S under session_sync lease `integration/main` epoch 1 (Codex relinquished).

**Coordination**:
- L0-fable registered in shared coordinator `var/coordination/tri-agent` (sequence 3).
- 69 inbox board messages acknowledged.
- "Integrate" and "green Andon" posted after split.

**Open Work**:
- Peers must rebase C01–C07 onto `integration/uos-swarm`.
- Default workspace update (deferred).
- CHK-09 math gates (Shannon Entropy, CCM, Trajectory Divergence, ITQS) pending tri-sovereign validation.
- Boundary review by AGY + Codex + Claude (tri-sovereign) pending.
