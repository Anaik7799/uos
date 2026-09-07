# 20260907-1756- Journal: Observable Predicates for LAW-VFS-05 and LAW-VFS-08

`#fractal-l0` `#fractal-l1` `#fractal-l2` `#fractal-l3` `#fractal-l4` `#fractal-l5` `#fractal-l6` `#fractal-l7` `#fractal-l8` `#fractal-l9` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#journal`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-vfs-law-predicates-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-1756-vfs-law-predicates-journal.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Clock**: host `2026-09-07T18:06:46Z` (chrony stratum 3). **Sa-plan**: plan `uos/agentic-infra-checklist/20260907-1722`, task `t3-vfs-predicates` (P2, score 96), preflight `PREFLIGHT_PASS`, worker `claude-fable-5.1-session-019m7SjJ`.

## 1. Scope & Trigger
Operator: "go further". First open item after the gate repair: the two VFS laws the repaired `selfcheck-vfs` gate reported `[UNRUN]`. Scope: `tools/uos` predicates and tests only; ZigVM sources were read, not changed.

## 2. Pre-State Assessment
LAW-VFS-05 (immutable snapshot reads) and LAW-VFS-08 (path canonicalization and boundary cage) had no predicate. The VFS analysis wiki (`docs/wiki/20260906-1620-…`) and ADR-046 record both as PASS with gates `G-VFS-SNAPSHOT` and `G-VFS-CAGE` that do not exist in `tools/uos`.

## 3. Execution Detail
Searched `engines/zigvm/src/prim_file.zig` and `bifs/file.zig` for the mechanisms each law names. LAW-VFS-05: `readFile` returns a caller-owned copy bounded by `.limited(max)` (`readFileAlloc`), and `pread` uses `readPositionalAll`, independent of the shared offset; bound the law to those two symbols with a label that states concurrent-writer isolation is not re-run. LAW-VFS-08: every operation is dirfd-relative (`root: Dir`) but there is no `RESOLVE_BENEATH`, `openat2`, or rejection of `..` or absolute paths anywhere in the two files; the law is not implemented. Bound it to `root: Dir && (RESOLVE_BENEATH || openat2)` so it turns green only when a jail is actually written, and relabelled it NOT IMPLEMENTED with the nonconformant wiki and ADR record named. Updated the gate test to expect exactly seven passing laws and exit 1.

## 4. Root Cause Analysis
The wiki and ADR-046 asserted gates that were never written; `selfcheck-vfs` then printed their PASS rows verbatim. Dirfd-relative access was mistaken for a jail: `openat` on a directory handle does not stop `../` or absolute paths from leaving it.

## 5. Fix Taxonomy
Evidence binding (documentation-grade predicates) plus one corrected nonconformance record. No runtime change. The missing jail is a ZigVM engineering gap, recorded for a separate task.

## 6. Patterns & Anti-Patterns Discovered
Pattern: a predicate written as the symbol that would exist once the mechanism is built (`RESOLVE_BENEATH`/`openat2`) keeps a gate honest today and self-clearing later. Anti-pattern: naming a gate in a ratification record before the gate exists.

## 7. Verification Matrix
| Check | Result |
|---|---|
| `gleam test` (tools/uos) | 27 passed, 0 failed |
| `gleam run -- selfcheck-vfs` | `7/8 VFS Laws Observed (FAIL)`, exit 1; LAW-VFS-08 `[UNRUN]` NOT IMPLEMENTED |
| Jail search (`RESOLVE_BENEATH`, `openat2`, `beneath`, `..` handling) in `engines/zigvm/src` | no matches outside tests |

## 8. Files Modified
| File | Change |
|---|---|
| `tools/uos/src/main.gleam` | `vfs_laws` rows 05 and 08; summary wording |
| `tools/uos/test/gate_verdict_test.gleam` | test renamed and tightened to 7 of 8 |

## 9. Architectural Observations
The ZigVM file seam is descriptor-relative by construction, which is the right foundation; the cage needs `openat2` with `RESOLVE_BENEATH` (Linux 5.6+) or explicit path normalization with rejection of absolute and parent components at the seam.

## 10. Remaining Gaps
Implement the jail in `prim_file.zig` (new sa-plan task under the ZigVM engine); correct or annotate the VFS wiki and ADR-046 (historical records are preserved; a nonconformance note belongs in a new ZK note).

## 11. Metrics Summary
| Metric | Value |
|---|---|
| Laws with observed predicates | 7 of 8 (was 6) |
| Laws not implemented | 1 (LAW-VFS-08) |
| Nonconformant ratification records found | 2 (wiki, ADR-046) |
| Tests | 27 passed |

## 12. STAMP & Constitutional Alignment
Hazard H-1 (green over defect) stays closed: the gate still fails. UCA "provided unsafe" (binding a weak keyword) was constrained by naming the exact mechanism symbols. Work ran under a claimed sa-plan lease with preflight pass; no Git inside UOS.

## 13. Conclusion
LAW-VFS-05 has evidence; LAW-VFS-08 is a real gap in ZigVM, now stated as such by the gate instead of hidden by an unconditional PASS. `verify-all` stays red for the right reason.

---
**Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md) · **Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md) · **Review Tome**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md)  
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · peer `vm-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.
