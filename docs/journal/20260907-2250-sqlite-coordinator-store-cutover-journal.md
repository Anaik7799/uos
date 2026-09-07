# 20260907-2250- Journal: SQLite Coordinator Store Integrated per the SQLite-Only Mandate

`#fractal-l0` `#fractal-l3` `#fractal-l6` `#fractal-l8` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#swarm` `#journal`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-2250-sqlite-coordinator-store-cutover-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-2250-sqlite-coordinator-store-cutover-journal.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Plan**: [stabilization and swarm convergence plan](http://nas-1.tail55d152.ts.net:4100/docs/docs/plans/20260907-2250-uos-stabilization-and-swarm-convergence-plan.md)  
**Clock**: host `2026-09-07T20:28:55Z`. **Sa-plan**: `uos/stabilization/20260907-2250`, task `s1-sqlite-coordinator-cutover`, P1, score 1280, preflight `PREFLIGHT_PASS`, worker session `0288c197`.

## 1. Scope & Trigger
Operator mandate issued this turn: **only use SQLite for JSON state storage to prevent corruption.** The structural fix already existed, built by session `656f0d2c`, stranded in a sibling workspace and never integrated. Scope: integrate into canonical, rehearse migration on copies only, no live cutover.

## 2. Pre-State Assessment
Canonical had no coordinator store. Two divergent stranded copies existed: `split-int` at 782 lines with 443 lines of tests, and `w-coverage2` at 749 and 376. `split-int` is newer and is the board-registered workspace of the author, so it was chosen. Two journal corruptions had already occurred on the file coordinator that day, and a **third occurred during this task**.

## 3. Execution Detail
Copied `session_store.gleam`, `session_store_ffi.erl`, `session_store_cli.gleam` and `session_store_test.gleam` into canonical, and added `esqlite` and `simplifile` to `gleam.toml`. The build then failed on three missing `session_sync` functions. Comparing the two `session_sync` modules showed `split-int` is a **strict superset**: seven new public functions, none removed, mostly private-to-public promotions. Backed up canonical and copied it. Build clean.

Migration was rehearsed twice against **copies** of the live journal, never the live directory.

## 4. Root Cause Analysis
The file journal has no enforcement. Any process that can write the directory can rewrite an event in place, forge a chain over the same sequence numbers, and stamp another session's identity. SQLite moves that enforcement below the application: triggers reject `UPDATE` and `DELETE`, and writers never supply sequence, digest or previous digest.

## 5. Fix Taxonomy
Integration of an existing, tested structural fix. No live cutover, no runtime change.

## 6. Patterns & Anti-Patterns Discovered
Pattern: enforcement belongs at the storage layer, where a well-behaved API cannot be the only defence. Anti-pattern found and named: a structural fix that is built, tested and then left in a sibling workspace is worth nothing to the system that needs it. Both corruptions and the third one all occurred **after** the fix existed.

## 7. Verification Matrix
| Check | Result |
|---|---|
| `gleam build` (apps/uos_swarm) | clean |
| `gleam test` (apps/uos_swarm) | 592 passed, **6 failed**: all six are the new `session_store` tests failing with `Undef`; every pre-existing test passes, so the `session_sync` superset broke nothing |
| `session_store_cli schema` | emits the full schema |
| `session_store_cli migrate` against a corrupted journal copy | **correctly refused** at sequence 437 |
| `session_store_cli migrate` against the repaired journal copy | `migrated_events: 468` |
| `session_store_cli verify` | `checked: 468, sequence_ok, chain_ok, digest_ok, triggers_present, unique_operations`, zero failures |
| **Falsifier**: raw `UPDATE` on `events` | refused, `events are append-only (19)` |
| **Falsifier**: raw `DELETE` on `events` | refused, `events are append-only (19)` |
| Live journal migrated | **no**, by design; copies only |

## 8. Files Modified
| File | Change |
|---|---|
| `apps/uos_swarm/src/uos_swarm/session_store.gleam` | New, 782 lines |
| `apps/uos_swarm/src/session_store_ffi.erl` | New, 173 lines |
| `apps/uos_swarm/src/session_store_cli.gleam` | New, 216 lines |
| `apps/uos_swarm/test/session_store_test.gleam` | New, 443 lines |
| `apps/uos_swarm/src/uos_swarm/session_sync.gleam` | Replaced with the superset, 927 to 1102 lines |
| `apps/uos_swarm/gleam.toml` | Added `esqlite`, `simplifile` |

## 9. Architectural Observations
The store's refusal to migrate a corrupt journal is the behaviour the file coordinator never had. During this task it refused a real corruption rather than a synthetic one, which is the strongest evidence available that the mandate is correct.

## 10. Remaining Gaps
The six `Undef` unit tests must be diagnosed before this is called green; the CLI exercises the same code paths successfully, so the fault is likely in the test harness rather than the store. Live migration and runtime cutover need separate authorization. The divergent `w-coverage2` copy is unreconciled.

## 11. Metrics Summary
| Metric | Value |
|---|---|
| Events migrated and chain-verified | 468 |
| Append-only falsifiers passed | 2 of 2 |
| Tests passed / failed | 592 / 6 |
| Journal corruptions observed today | 3 |

## 12. STAMP & Constitutional Alignment
Loss L-3 evidence contamination, hazard H-3. UCA "not provided" (no enforcement against in-place rewrite) constrained by SQL triggers, demonstrated by two falsifiers. UCA "provided unsafe" (writer supplies its own sequence and digest) constrained by the store deriving both. UCA "wrong timing" constrained by `BEGIN IMMEDIATE`. No live state was migrated and no runtime was cut over. Work under a claimed lease with passing preflight; no Git inside UOS.

## 13. Conclusion
The fix the system needed all day is now in the canonical workspace and provably refuses the exact attack that stalled the swarm three times. It is not yet green: six unit tests fail with `Undef` and the live cutover remains unauthorized.

---
**Master ZK MOC**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260905-1801-moc-uos-unified-master.md) · **Wiki Corpus Index**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/wiki/20260905-1801-uos-zk-km-corpus-index.md)  
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.
