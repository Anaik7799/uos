# 20260907-1756- Journal: tools/uos Gate Integrity Repair (checklist, selfcheck-vfs, selfcheck-15-cycles, selfcheck-inference)

`#fractal-l0` `#fractal-l1` `#fractal-l2` `#fractal-l3` `#fractal-l4` `#fractal-l5` `#fractal-l6` `#fractal-l7` `#fractal-l8` `#fractal-l9` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#journal`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-tools-uos-gate-integrity-repair-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-tools-uos-gate-integrity-repair-journal.md)  
**Cockpit**: [http://nas-1.tail55d152.ts.net:4100/](http://nas-1.tail55d152.ts.net:4100/) · **Planning**: [http://nas-1.tail55d152.ts.net:4100/planning](http://nas-1.tail55d152.ts.net:4100/planning) · **Wiki**: [http://nas-1.tail55d152.ts.net:4100/wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · **ZK**: [http://nas-1.tail55d152.ts.net:4100/zk](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Parent finding**: [Checklist and oracle map, section 6.2](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-1756-production-agent-infrastructure-fractal-checklist-and-oracle-map.md)  
**Clock**: host `2026-09-07T17:53:17Z` (chrony stratum 3, leap Normal). **Revision**: jj working copy `umvyzluq` (re-described during the task by a concurrent writer; last seen `fe972945`). **Sa-plan**: plan `uos/agentic-infra-checklist/20260907-1722`, task `t2-gate-integrity` (depends on `t1-fractal-checklist`), class P1, score 768, preflight `PREFLIGHT_PASS`, worker `claude-fable-5.1-session-019m7SjJ`, attempt 1.

## 1. Scope & Trigger

Operator said "continue" after the checklist delivery; the first follow-up in its section 6.3 is the P1 evidence-integrity finding: four `tools/uos` commands printed green summaries and returned 0 without consulting their checks. Scope: `tools/uos` only (Gleam CLI plus its Erlang FFI and tests). No runtime service, rule, skill or agent surface changed.

## 2. Pre-State Assessment

`Checklist` computed 17 booleans and then printed `Summary: 18/18 Checks Passed (100% Green)` and returned 0 unconditionally. `SelfcheckVfs` and `Selfcheck15Cycles` printed fixed `[PASS]` lines with no predicates. `SelfcheckInference` checked that 11 files exist and printed "15/15 selfchecks passing" without running the worker. `VerifyAll` summed these exit codes, so it could never report a failure from them. The existing test file asserted only green paths.

## 3. Execution Detail

1. Created task `t2-gate-integrity`, wrote its SC-RISK-PRIORITY-001 record (C4 T4 F4 Dep3 I4; FM-GATE-001 S4 O4 Det4 RPN64), ran `--preflight` (pass), claimed with a 4-hour lease.
2. Added pure helpers `count_passed`, `exit_for` (empty list fails closed), `summary_line`, `status_tag`, `inventory_tag`, `fail_tag`, `inference_selfcheck_ok`, and data functions `vfs_laws`, `ev_cycle_records`.
3. Bound `Checklist` to the conjunction of its 18 checks.
4. Rewrote `SelfcheckVfs`: six laws bound to observed source predicates (`root: Dir`, `AT_SYMLINK_NOFOLLOW`, `rename`, `PrimError` in `prim_file.zig`; bevy/graphite absence in `build.zig`; `fencing_token` in `sa_plan_store.ml`); LAW-VFS-05 and LAW-VFS-08 print `[UNRUN]` and fail closed.
5. Rewrote `Selfcheck15Cycles` as an `[INVENTORY]` of the ratification record file per EV-25..EV-39; summary states it is not fresh admission evidence.
6. Added `run_command/3` to `uos_ffi.erl` (`spawn_executable` port from the repo root, stderr merged, exit status captured, timeout closes the port and returns 124; no shell).
7. Rewrote `SelfcheckInference` to execute `python3 services/inference/max/max_worker.py --selfcheck` (60 s bound) and bind rows MAX-02..MAX-09 to the worker's output, MAX-10 to the seven tool names in `mcp/tools.gleam`, MAX-11 to the interlock symbol in `mcp/server.gleam`, MAX-12 to manifest purity, MAX-13 to the storage serial in `spec.rs`; the "supervised daemon" wording was removed because no supervisor spawns the worker.
8. Added `test/gate_verdict_test.gleam` (13 tests) and ran the suite and the commands.

## 4. Root Cause Analysis

The verdict and the checks were separate code paths: booleans were printed row by row, but the summary and return value were literals. Later commands copied that shape without any predicates at all. Nothing in the test suite asserted a red path, so the defect was invisible to `gleam test`.

## 5. Fix Taxonomy

Correctness fix in a verification tool (Gleam and Erlang), plus tests. Behaviour change: `selfcheck-vfs` and therefore `verify-all` now exit 1 on the current tree, which is the truthful result.

## 6. Patterns & Anti-Patterns Discovered

Pattern adopted: verdict derived by folding a list of `Bool` observations through one `exit_for`; every printed row states what was observed; `[UNRUN]` is a first-class, failing state. Anti-pattern removed: literal summary strings and return values decoupled from checks. Remaining anti-pattern: ten other selfchecks still equate file presence with "100% Green" (listed in the checklist document section 6.2).

## 7. Verification Matrix

| Check | Result |
|---|---|
| `gleam build` (tools/uos) | clean, no warnings |
| `gleam test` (tools/uos) | 27 passed, 0 failed (14 pre-existing + 13 new) |
| `gleam run -- checklist` | `18/18 Checks Passed (PASS)`, exit 0 |
| `gleam run -- selfcheck-vfs` | `6/8 VFS Laws Observed (FAIL)`, exit 1 (LAW-VFS-05, LAW-VFS-08 UNRUN) |
| `gleam run -- selfcheck-15-cycles` | `15/15 Ratification Records Present (PASS)`, exit 0, inventory only |
| `gleam run -- selfcheck-inference` | `13/13 (PASS)`, exit 0; worker executed, exit 0 |
| `gleam run -- verify-all` | `VERIFICATION RESULT: FAILURES DETECTED`, exit 1 |
| Risk preflight / active-check | `PREFLIGHT_PASS`; active-check result recorded in the sa-plan completion receipt |
| Negative-path unit tests | `exit_for([True, False]) == 1`, `exit_for([]) == 1`, `inference_selfcheck_ok(1, green) == False`, `inference_selfcheck_ok(0, "") == False` |

## 8. Files Modified

| File | Change |
|---|---|
| `tools/uos/src/main.gleam` | 100 lines removed, 262 added: verdict helpers, four gate bodies, `run_command` external, imports |
| `tools/uos/src/uos_ffi.erl` | 28 lines added: `run_command/3`, `collect/3`, export |
| `tools/uos/test/gate_verdict_test.gleam` | New, 110 lines, 13 tests |
| `docs/design/20260907-1756-production-agent-infrastructure-fractal-checklist-and-oracle-map.md` | Section 6.2 repair table and 6.3 follow-up updated |
| `var/sa-plan/uos.sqlite3` | Task t2 create, claim, complete (through `tools/sa-plan`) |

## 9. Architectural Observations

A gate is only as honest as the binding between observation and verdict. The `run_command` port makes execution-based gates cheap (the worker selfcheck costs half a second), so the remaining existence-only selfchecks can be converted the same way: run the suite, parse a stable final line, bind rows to output.

## 10. Remaining Gaps

Observable predicates for LAW-VFS-05 (immutable snapshot reads) and LAW-VFS-08 (boundary cage); execution-based rewrites for the ten existence-only selfchecks; a validator for `c3i_fractal_observability_spec.json`; an in-repo Lean build. `verify-all` stays red until LAW-VFS-05 and LAW-VFS-08 have evidence or are removed from the law list by an authorized decision.

## 11. Metrics Summary

| Metric | Value |
|---|---|
| Commands repaired | 4 of 14 non-gating or existence-only commands |
| Tests | 27 total, 13 new, 0 failures |
| Worker selfcheck wall time | about 0.5 s |
| Net source change | +290 / -100 lines across 3 files |
| `verify-all` exit before / after | 0 / 1 |

## 12. STAMP & Constitutional Alignment

Hazard H-1 (green gate over a defect) is closed for the four commands: UCA "not provided" (failure never surfaced) is constrained by `exit_for`; UCA "provided unsafe" (fixed PASS lines) is constrained by binding every row to a predicate or marking it `[UNRUN]`. The change adds no shell execution, no network, no new dependency (Zero-Muda intact). Work ran only under a claimed sa-plan lease with a passing preflight (`SC-JIDOKA-001`, `SC-RISK-CHECK-001`). No Git command inside UOS.

## 13. Conclusion

The four gates can now fail, and the first thing they did was fail honestly: `verify-all` reports two VFS laws without evidence. That red is the deliverable. The pattern (observation list, one fold, explicit UNRUN) is ready to be applied to the ten remaining existence-only selfchecks.

---

**Previous:** [Checklist and oracle map](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-1756-production-agent-infrastructure-fractal-checklist-and-oracle-map.md) · **Next:** LAW-VFS-05 / LAW-VFS-08 predicates, then the remaining selfchecks  
**Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md) · **Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md) · **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md)  
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · peer `vm-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.
