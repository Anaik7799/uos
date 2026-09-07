# 20260907-2250- Journal: Forecast History Persisted and Made Scorable

`#fractal-l3` `#fractal-l5` `#fractal-l8` `#rocha-semiotics` `#cybernetics` `#km-triad` `#zk-adr` `#zero-muda` `#checklist-nav` `#tailscale-web` `#stamp-stpa` `#sa-plan` `#journal`

**Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-2250-forecast-history-store-journal.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/journal/20260907-2250-forecast-history-store-journal.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)  
**Transclusions**: `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`  
**Plan**: [stabilization and swarm convergence plan](http://nas-1.tail55d152.ts.net:4100/docs/docs/plans/20260907-2250-uos-stabilization-and-swarm-convergence-plan.md)  
**Clock**: host `2026-09-07T20:57:01Z`. **Sa-plan**: task `s4-forecast-history-store`, P2, score 48, worker session `0288c197`.

## 1. Scope & Trigger
Convergence plan item `s4`, operator instruction "do s3 and s4". The forecaster is 901 lines wired into six callers but retained nothing, so the Brier calibration required by `SC-HIVE-KPI-001` was uncomputable.

## 2. Pre-State Assessment
`apps/cepaf_gleam/src/cepaf_gleam/ha/forecast_store.gleam` already existed, 76 lines, authored by another session under a different plan id (`PLAN-UOS-STABILIZE-001`). **Coordination decision: extend, never duplicate.** What it had: open, exec and close bindings, a `StoredForecast` type, the table DDL, and a pure Brier calculation.

What it lacked was the entire persistence round trip. `sqlite_q` was not bound at all, so nothing could read the ledger; there was no insert and no resolve; and `calculate_calibration` scored a list passed in from memory. Nothing that was ever stored could be scored. Its only caller was its own test.

## 3. Execution Detail
Added the missing half, additively, leaving the existing type, DDL columns and pure function untouched so the other session's work and tests still hold.

- Bound `sqlite_q` and routed **every** write through it with bound parameters rather than string-built SQL, because unparameterized SQL is precisely what the zero-trust dispatch interceptor traps.
- `record_prediction`, `resolve_prediction`, `load_records`, `calibration_from_db`.
- Positional row decoding, tolerant of SQLite returning an integer for a REAL column holding a whole number, which would otherwise reject a stored 0 or 1.
- Three triggers in `init_schema` implementing the mandate's precommitment rule: a forecast may not be rewritten after it is made, a resolved forecast may not be re-resolved, and nothing may be deleted.

## 4. Root Cause Analysis
The calibration function was written before the storage it was meant to score. With no read path the module looked complete and computed a number, but only over data a caller already held, which is not calibration.

## 5. Fix Taxonomy
Capability completion plus integrity enforcement. Additive; no existing behaviour changed.

## 6. Patterns & Anti-Patterns Discovered
Pattern: a scoring function is only meaningful when the thing it scores cannot be edited after the outcome is known. The triggers are not incidental hardening, they are what makes the Brier number carry information at all. Anti-pattern found: a pure metric function with no data path, which passes its tests while measuring nothing.

## 7. Verification Matrix
| Check | Result |
|---|---|
| `gleam build` (apps/cepaf_gleam) | clean |
| `gleam test` (apps/cepaf_gleam) | **10,563 passed, 0 failed** |
| New tests | 5: round trip, unresolved-only, rewrite refusal, re-resolve refusal, delete refusal |
| Round trip | 3 recorded, 2 resolved, Brier 0.0 over denominator **2, not 3** |
| Zero denominator | reported `Undetermined`, never 0.0 |
| **Independent raw SQLite**: rewrite an unresolved forecast | refused, "a forecast may not be rewritten after it is made" |
| **Independent raw SQLite**: change its aspect | refused, same |
| **Independent raw SQLite**: flip a recorded outcome | refused, "a resolved forecast may not be re-resolved" |
| **Independent raw SQLite**: delete the row | refused, "forecast ledger is append-only" |
| Legitimate resolve still works | yes, both rows resolved normally |
| Stored bad prediction after all attacks | `x1, 0.1, observed 1, resolved 1`, unchanged |

## 8. Files Modified
| File | Change |
|---|---|
| `apps/cepaf_gleam/src/cepaf_gleam/ha/forecast_store.gleam` | 76 to 210 lines: parameterized query binding, record, resolve, load, calibration from store, tolerant decoding, three triggers |
| `apps/cepaf_gleam/test/forecast_store_test.gleam` | 5 tests appended; the three existing tests untouched |

## 9. Architectural Observations
The denominator behaviour matters as much as the score. A ledger of unresolved predictions now reports `Undetermined` with its reason rather than a flattering 0.0, which is the rule the KPI mandate states as "a zero denominator is unavailable, not perfect performance".

## 10. Remaining Gaps
The schema still lacks fields the KPI mandate names: horizon, expiry, source or candidate fingerprint, and confidence grade. I deliberately did not add columns, because another session owns this module and a `CREATE TABLE IF NOT EXISTS` change would silently not apply to existing databases. That belongs to the owner with a migration. Nothing in `fractal_forecast.gleam` calls `record_prediction` yet, so the ledger is available but not yet fed by the forecaster.

## 11. Metrics Summary
| Metric | Value |
|---|---|
| Module lines before / after | 76 / 210 |
| Tests added / suite total | 5 / 10,563 |
| Triggers added and independently verified | 3 of 3 |
| Existing functions changed | 0 |

## 12. STAMP & Constitutional Alignment
Loss L-1 false conformance. UCA "provided unsafe" (publishing a calibration score computed over an editable ledger) is constrained by the three triggers, each verified outside the test suite in raw SQLite. Writes are parameterized, satisfying the raw-SQL rule. The operator's SQLite-only mandate is honoured: this state is SQLite, not JSON files. Lease held; preflight and active-check passed; no Git inside UOS.

## 13. Conclusion
Forecasting has a durable memory, and the memory cannot be edited to flatter itself. Calibration is computable now, and the first thing it will honestly report is that there are almost no resolved predictions yet.

---
**UOS footer**: `nas-1.tail55d152.ts.net:4100` · OTP 29 BEAM · admission `NOT_ADMITTED`.
