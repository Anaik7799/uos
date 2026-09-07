# 20260907-1756- Journal: Wave 3/4 Inventory Binding and Executed Mirage Gates

`#fractal-l0` `#fractal-l1` `#fractal-l2` `#fractal-l3` `#fractal-l4` `#fractal-l5` `#fractal-l6` `#fractal-l7` `#fractal-l8` `#fractal-l9` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#journal`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-wave-and-mirage-gate-evidence-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-wave-and-mirage-gate-evidence-journal.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Clock**: host `2026-09-07T19:59:17Z` (chrony stratum 3). **Sa-plan**: plan `uos/agentic-infra-checklist/20260907-1722`, task `t7-wave-and-mirage-gates` (P1, score 768), preflight `PREFLIGHT_PASS`, worker `claude-fable-5.1-session-019m7SjJ`.

## 1. Scope & Trigger
Operator: "continue". The next SOP item was the ZigVM path jail, which is **blocked**: no Zig toolchain exists on this host (`zig` is absent from PATH, no vendored toolchain, no `zig-out`), so jail code could be written but neither built nor tested, which yields zero operational credit under two-key verification. The scan for that decision surfaced a worse defect than the eleven existence-only gates: two gates with **zero predicates**. This slice repairs those two and converts the four Mirage gates to execution.

## 2. Pre-State Assessment
`selfcheck-wave3-cycles` (EV-55..EV-69) and `selfcheck-wave4-cycles` (EV-70..EV-84) printed 30 fixed `[PASS]` lines and returned 0 with no `file_exists` or `file_contains` call anywhere in either body: the same defect class repaired in `t2-gate-integrity`, missed then because that task scanned only the gates it had already identified. The four Mirage gates checked 30 file paths between them and claimed "100% Green", while the Hermes suites they represent print their own caveats: "Solo5 deployment remains NOT_VERIFIED", "deployment NOT_VERIFIED", "UNIKERNEL DEPLOYMENT NOT VERIFIED".

## 3. Execution Detail
1. Located a ratification record for each of EV-55 to EV-84 (30 of 30 found across five handover and journal documents) and built `wave3_records` and `wave4_records` binding every row to its record path.
2. Rewrote both wave gates: rows print `[INVENTORY]` or `[MISSING]`, the summary states "inventory; not fresh admission evidence", and the exit code folds all fifteen predicates. The word PASS no longer appears in either gate.
3. Rewrote the four Mirage gates to keep their source predicates and add an executed suite row: `test_mirage_core`, `test_mirage_migration`, `hermes_mirage_runner selftest` and `test_mirage_hypervisor`, each through `run_command` with a 120 s bound.
4. Added `count_pass_lines`, `suite_pass_ok` (exit 0 plus a PASS-line floor plus a terminal phrase) and `last_line`. Each Mirage gate now prints a `[SUITE-VERDICT]` row reproducing the suite's own final line, so the deployment caveat appears in the gate output instead of being contradicted by it.
5. Added 5 tests (37 total in `tools/uos`).

## 4. Root Cause Analysis
Same shape as t2: verdicts were literals. The wave gates were the extreme case, with no observation at all. The Mirage gates had observations but of the wrong thing: file presence stood in for suite execution, and the gate's summary asserted a readiness the suite explicitly denied.

## 5. Fix Taxonomy
Verification-tool correctness plus tests. Behaviour change: six gates can now fail. No runtime change.

## 6. Patterns & Anti-Patterns Discovered
Pattern adopted: when a suite states its own limits, the gate reproduces that line verbatim rather than summarizing over it. Anti-pattern confirmed: a gate whose summary is more confident than the evidence it runs on. Process note: my first PASS-line floors were one too high for three suites because the earlier count included the terminal "passed" line; the gate failed closed and exposed my error rather than passing, which is the property being built.

## 7. Verification Matrix
| Check | Result |
|---|---|
| `gleam build` (tools/uos) | clean |
| `gleam test` (tools/uos) | 37 passed, 0 failed (5 new) |
| `selfcheck-wave3-cycles` / `selfcheck-wave4-cycles` | 15/15 records present, exit 0, labelled inventory |
| **Negative control**: one record moved aside | 13 rows `[MISSING]`, `2/15 (FAIL)`, exit 1; record restored byte-identical |
| `selfcheck-mirage` | 10/10, exit 0, suite exit 0, 4 PASS lines, verdict "Solo5 deployment remains NOT_VERIFIED" |
| `selfcheck-mirage-migration` | 10/10, exit 0, suite exit 0, 15 PASS lines, verdict "deployment NOT_VERIFIED" |
| `selfcheck-mirage-prod` | 9/9, exit 0, runner exit 0, 6 PASS lines, verdict "UNIKERNEL DEPLOYMENT NOT VERIFIED" |
| `selfcheck-mirage-tenders` | 5/5, exit 0, probe exit 0, 11 PASS lines, negative controls passed |
| `verify-all` | exit 1, failing on LAW-VFS-08 alone |

## 8. Files Modified
| File | Change |
|---|---|
| `tools/uos/src/main.gleam` | Six gate bodies; `wave3_records`, `wave4_records`, four Mirage suite descriptors, `count_pass_lines`, `suite_pass_ok`, `last_line` |
| `tools/uos/test/gate_verdict_test.gleam` | 5 tests |

## 9. Architectural Observations
The Hermes Mirage suites are unusually honest: each ends by naming what it did not verify. Wiring gates to reproduce that line costs nothing and removes a whole class of overclaim. Five existence-only selfchecks remain (`hermes-bionic`, `omni-matrix`, `c3i-knowledge`, `vertical-slice`, `zigvm-add`, `raga`, `forecast`); those whose evidence is a Gleam test file cannot be converted the same way, because the cepaf suite takes about twenty minutes and is too slow for a gate.

## 10. Remaining Gaps
ZigVM path jail: **blocked on toolchain**, not on design; the oracle from t6 is the specification and a Zig toolchain is the prerequisite. The remaining existence-only selfchecks need either a fast per-module test target or an honest `[INVENTORY]` relabel. The EV records bound here are handover documents, not fresh runtime evidence, which is why every row says inventory.

## 11. Metrics Summary
| Metric | Value |
|---|---|
| Gates repaired this slice | 6 (2 zero-predicate, 4 existence-only) |
| Unconditional PASS lines removed | 30 |
| Suites now executed per gate run | 4 Mirage (about 0.8 s total) |
| Tests | 37 passed, 5 new |
| Gates repaired across t2, t5 and t7 | 10 |

## 12. STAMP & Constitutional Alignment
Hazard H-1 closed for six more gates. UCA "not provided" constrained by folding every predicate into the exit code; UCA "provided unsafe" constrained by binding each row to an observation and reproducing the suite's own caveat; UCA "duration" constrained by the 120 s per-suite bound. The negative control demonstrates the gate can fail. Sa-plan lease held with passing preflight and active-check; no Git inside UOS; no new dependency.

## 13. Conclusion
Thirty fabricated PASS lines are gone and four unikernel gates now run the suites they claimed to represent, caveats included. `verify-all` fails on one row, the missing ZigVM jail, which is a blocked engineering task rather than a gate defect.

---
**Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md) · **Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md) · **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md)  
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · peer `vm-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.
