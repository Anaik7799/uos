# 20260907-1756- Journal: Execution-Based sa-plan Selfcheck in tools/uos

`#fractal-l0` `#fractal-l1` `#fractal-l2` `#fractal-l3` `#fractal-l4` `#fractal-l5` `#fractal-l6` `#fractal-l7` `#fractal-l8` `#fractal-l9` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#journal`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-saplan-selfcheck-execution-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-saplan-selfcheck-execution-journal.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Clock**: host `2026-09-07T18:12:37Z` (chrony stratum 3). **Sa-plan**: plan `uos/agentic-infra-checklist/20260907-1722`, task `t5-saplan-selfcheck-exec` (P2, score 216), preflight `PREFLIGHT_PASS`, worker `claude-fable-5.1-session-019m7SjJ`.

## 1. Scope & Trigger
Operator: "go further". Third SOP follow-up slice: convert the execution authority's own gate from file presence to execution. Scope: `tools/uos` only.

## 2. Pre-State Assessment
`selfcheck-sa-plan` checked that 13 executables existed and then printed twelve fixed `[PASS] SUITE` rows plus six policy rows and `235 Laws … 100% Green`. The suites themselves take about 0.1 s each and were never run by the gate.

## 3. Execution Detail
1. Added `sa_plan_suites()` (13 suites: the twelve listed plus `test_sa_plan_observation`, which existed as an executable but was not in the gate), each with a minimum `ok`-line floor taken from the law count the suite has always reported, or a success phrase for the one suite that reports prose.
2. Rewrote `SelfcheckSaPlan` to execute each suite through `run_command` (60 s bound), bind the row to exit 0 plus the floor, and print the observed exit code and `ok` count on the row. Control rows: `tools/sa-plan status` executed (exit 0) and the Jidoka stop-line symbols present. Policy documents are printed as `[INVENTORY]`.
3. Fixed `run_command` in `uos_ffi.erl` to resolve repository-relative executable paths against the root; the first run returned 127 for every suite because `os:find_executable` only searches `PATH`.
4. Added four tests (`count_ok_lines`, `suite_ok` floors and prose, thirteen suites and exit 0).

## 4. Root Cause Analysis
Same shape as t2: rows were literals, not observations. The relative-path defect in the runner was a latent bug introduced in t2 that this slice exposed.

## 5. Fix Taxonomy
Verification-tool correctness (Gleam and Erlang) plus tests. No runtime change.

## 6. Patterns & Anti-Patterns Discovered
Pattern: a suite row carries its own evidence (exit code and observed law count) in the printed line. Anti-pattern removed: a fixed "235 Laws" claim; the gate now prints the floor it enforces (176) and the observed counts, which are higher.

## 7. Verification Matrix
| Check | Result |
|---|---|
| `gleam test` (tools/uos) | 31 passed, 0 failed |
| `gleam run -- selfcheck-sa-plan` | 19/19 PASS, exit 0; 13 suites executed, all exit 0; observed ok-lines 108, 50, 7, 10, 8, 19, 7, 12, 3, 5, 6, 17 plus one prose suite |
| `gleam run -- verify-all` | exit 1, failing only on LAW-VFS-08 (not implemented) |
| Suite behaviour from repository root | identical to running from `engines/hermes` (checked before patching) |

## 8. Files Modified
| File | Change |
|---|---|
| `tools/uos/src/main.gleam` | `SelfcheckSaPlan` body, `sa_plan_suites`, `count_ok_lines`, `suite_ok` |
| `tools/uos/src/uos_ffi.erl` | relative path resolution in `run_command` |
| `tools/uos/test/gate_verdict_test.gleam` | four tests |

## 9. Architectural Observations
The pattern generalizes: every remaining existence-only selfcheck whose evidence is a runnable suite (`dune runtest` for Mirage, the Gleam suites for forecast, raga, ADD) can be converted the same way, with the gate refusing to claim more than the suite printed.

## 10. Remaining Gaps
The gate does not rebuild the executables; stale binaries would be executed as-is (a dune build step or a source-digest check is the next improvement). Remaining existence-only selfchecks: hermes-bionic, omni-matrix, c3i-knowledge, wave3, wave4, vertical-slice, zigvm-add, raga, the three mirage commands, forecast.

## 11. Metrics Summary
| Metric | Value |
|---|---|
| Suites executed per gate run | 13 (was 0) |
| Gate wall time | about 2 s |
| Enforced law floor | 176 (observed total higher) |
| Tests | 31 passed |

## 12. STAMP & Constitutional Alignment
Hazard H-1 closed for this gate; UCA "duration" (hung suite) constrained by the 60 s bound returning 124. Sa-plan lease held; preflight and active-check passed; no Git inside UOS.

## 13. Conclusion
The execution authority's gate now runs the execution authority's tests. `verify-all` remains red for exactly one reason, the missing ZigVM path jail, which is a real defect and not a gate defect.

---
**Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md) · **Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md) · **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md)  
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · peer `vm-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.
