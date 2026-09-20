# 20260930-0451 Fractal RCA and preserved-history recovery

Observed: 2026-09-30, 04:21–04:56 UTC. Verdict: **DEVELOPMENT_REVIEW_PASS; LIVE_RESTORATION_HOLD**.
Tags: #fractal-l0 #fractal-l2 #fractal-l4 #fractal-l8 #zk-adr #zero-muda
Sa-plan: `uos/fractal-recovery/20260930-0421`, RCA attempt 1; independent REVIEW attempt 1.
Scope: operator-requested diagnosis, source repair, isolated candidates and runtime verification. Production admission is not granted.

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Receipt](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260930-0451-fractal-recovery-evidence/20260930-0451-recovery-receipt.json)

## 1. Scope & Trigger

The operator requested fractal RCA and fixes for coordinator/cycle integrity failures and ecology startup rejection of changed MAX metadata, with independent recovery/release safeguards intact. This task repairs demonstrated producers and release binding, preserves every original history, and verifies candidates. Engine 5: executable contracts and regression falsifiers are evidence; no new Lean/Gospel proof or full system admission is claimed.

## 2. Pre-State Assessment

The SQLite coordinator held 117 events: rows 66–117 had digest mismatches and unsupported `ratify_cycle` operations; typed replay already failed at row 3 because its actor had not registered. The separate legacy journal contained 1,762 records, with its last record failing digest validation. These histories diverge and cannot be silently merged.

The cycle ledger contained 550 rows and 71 digest defects: 333–352, 427, and 501–550. The first complete valid prefix ends at 332. Valid-looking rows after a defective row do not repair the chain. Original auxiliary tables held 24 governance holds, six releases and one EV-999 test evidence row.

The ecology production instance was failed because its immutable package referred to editable workspace `pixi.toml` and `pixi.lock`. Existing developer changes added pip-related metadata. Those edits were preserved. Engine 7: the initial state was mixed availability with failed authority integrity; no calibrated Kalman estimate is asserted.

## 3. Execution Detail

Canonical Sa-plan and fresh source-bound risk checks governed development. Consistent original database backups and every legacy event were preserved in the private, mode-700 directory `/home/an/uos-recovery-candidates/20260930-0421-fractal-rca`. No canonical database was replaced, no live journal tail was removed, and no digest was re-signed.

The coordinator now screens inserted payloads for typed JSON shape, matching envelope/columns, known operations, required registration fields and registered actors. It still verifies full digest and typed replay in the transactional writer/reader; SQL screening is not a complete semantic or cryptographic admission mechanism.

Cycle append now starts an immediate transaction, verifies the existing chain, appends only after successful verification, and rolls back failure. A new no-replace trigger blocks SQLite REPLACE from deleting historical rows through uniqueness collisions. The public module interface hides the unchecked append helper.

Release packaging snapshots MAX manifest/lock into a content-addressed, read-only capsule referencing the existing realized environment. Strict verification checks content, inventory, permissions, environment link and interpreter binding. An explicit dependency-only rebind command preserves old runtime payloads while constructing a new non-admitted candidate; the final selected development candidate instead contains the complete rebuilt web application closure and the new per-invocation runtime guard.

The runtime guard rechecks MAX metadata, capsule identity and directory chain, environment link and interpreter identity before invocation. No package or model was installed or copied. Existing OCaml and Mojo commands agree on strict package verification.

A discovered empty `.git` marker was preserved outside the workspace. The fresh 31-check toolchain preflight passed after its removal. Its creator is unknown. Engine 6: these changes add structural refusal at the write/invocation boundary; no new Rete admission is inferred.

## 4. Root Cause Analysis

ACH disconfirmation:

| Hypothesis | Disconfirming observation | Assessment |
|---|---|---|
| H1: Formatting alone explains coordinator failure | Unsupported operations, mismatched hashes and an unregistered actor occur together | Rejected as sufficient explanation |
| H2: Append-only triggers prevent invalid history | Raw inserts could bypass typed validation; SQLite REPLACE can bypass ordinary delete-trigger protection | Rejected; structural defect now covered by regression |
| H3: Re-signing every row is valid recovery | A digest proves byte identity, not origin or authority | Rejected |
| H4: Ecology runtime itself cannot perform MAX inference | Rebuilt immutable candidate starts and returns actual MAX graph probabilities | Rejected for the tested operation |
| H5: Mutable dependency location caused the startup rejection | Old release binds developer metadata paths; frozen capsule survives subsequent source edits | Supported; guard was correctly refusing drift |

Fractal RCA, with all eight required fields:

| Layer | Symptom | Cause hypothesis/evidence | Constraint | Owner | Containment | Falsifier | Recovery |
|---|---|---|---|---|---|---|---|
| L0 governance | No trustworthy live recovery selection | SQLite and legacy lineages diverge; recover-stage is explicitly evidence-only | No source review or candidate lease grants live authority | Operator / admitted Gleam recovery controller | LIVE_RESTORATION_HOLD | Candidate review alone enables effects | Explicit lineage decision and typed, fenced activation |
| L2 coordination | Coordinator digest/replay refusal | 52 malformed unsupported rows; replay fails at 3 | Typed command and actor history required | Gleam session store | Preserve originals; reject malformed raw inserts | Incomplete registration poisons a fresh store | Reviewed 1,761-event candidate; fresh sessions/leases only after activation |
| L4 evidence | 71 cycle digest defects | Unsafe append lacked prior-chain validation; raw SQL could bypass caller validation | No overwrite, re-signing or false admission | Hermes cycle ledger | Transactional verification, no-replace trigger, all holds retained | Corrupt chain accepts a new append, or REPLACE removes a row | Reviewed 332-row candidate; 218 excluded tail rows remain archived |
| L8 runtime | MAX manifest startup rejection | Immutable release referenced mutable workspace inputs | Startup and effect-time dependencies must agree | OTP ecology service / release packager | Frozen metadata, environment/interpreter checks | Redirected link or changed interpreter is accepted | Full rebuilt candidate passes private startup, MAX and clean shutdown |

Writer identity and intent behind the historical corruption remain unproved. The source changes prevent demonstrated bypass patterns; they do not retrospectively authenticate records.

## 5. Fix Taxonomy

Poka-Yoke: typed insert screening, hidden unchecked append helper, content-addressed metadata and interpreter binding. Jidoka: corrupt history refuses append and drift refuses invocation; live restoration stays HOLD. Muda reduction: existing realized toolchains/environments, bounded staging, no repeated blind restarts, and preserved failures rather than regenerated evidence.

## 6. Patterns & Anti-Patterns Discovered

Append-only storage is weaker than a verified append protocol. SQLite uniqueness replacement needs its own guard. A release can be immutable while its dependencies remain mutable. Startup checks alone do not protect later invocations.

Independent review caught missing governance holds in the initial cycle candidate, incomplete raw registration screening, unchecked capsule links, and a startup/runtime interpreter-binding mismatch. All were repaired. Devil's Advocate/Engine 4: passing prefix integrity still does not establish writer provenance, selected lineage or production authority. Same-UID writers can still bypass file permissions and SQL policy; OS-level writer isolation is not claimed.

## 7. Verification Matrix

Engine 2/STANAG: fresh local observations are assessed B2 within their stated scope; independent review separately checked exact source/candidate bytes. These grades do not grant system admission.

| Check | Result | Limit |
|---|---|---|
| Full isolated swarm suite | 671 passed, 0 failures | Development; includes 33 focused coordinator/recovery tests |
| Coordinator candidate | 1,761 events; sequence, chain, digest, replay, triggers and uniqueness PASS | Legacy prefix, not selected live authority |
| Cycle regressions | Positive append, corrupt-chain refusal, REPLACE refusal and rollback PASS | Bounded in-memory cases |
| Cycle candidate | 332 rows CHAIN_INTACT; all 24 original holds equal; zero releases/evidence copied | Excluded 218 rows remain in original; hold-release provenance unresolved |
| Ecology EUnit | 7 passed, including real MAX and dependency-tamper refusal | Test build exposes internal guard only for validation |
| Release selftests | 23 passed | Filesystem/verification falsifiers, not global formal proof |
| Full development web build | PASS | Existing unused-term warning retained |
| Final package | 1,223 files; 30,692,878 payload bytes; strict OCaml/Mojo verification PASS | Application admitted=false |
| Final private runtime | Actual OTP 29 / ERTS 17.0.5; cycle 24 to 81; zero restarts | Private loopback mapping at Tailnet FQDN, not production availability |
| Actual MAX | Engine 26.5.0, modular_max_graph; probability 0.9820137619972229 | Known linear-softmax input; no broad inference claim |
| Final shutdown | inactive/dead, Result=success, ExecMainStatus=0 | Owned staging service only |
| Toolchain | 31 checks PASS | Provisioning/admission not inferred |
| Independent review | DEVELOPMENT_REVIEW_PASS / LIVE_RESTORATION_HOLD | Canonical REVIEW attempt 1 completed |

Final release: `var/releases/ecology/20260930-0408-346e2b85ebdb3aac7e01fce61342b7db1edfae123df47200b621dd3175274a39`.
Candidate: `346e2b85ebdb3aac7e01fce61342b7db1edfae123df47200b621dd3175274a39`.
Payload: `d056f875a50fa82d8a591f8f63592b8328c41f41aa177b38c8973a3edeacc5f3`.
Source manifest SHA256: `b53401bc85ff18ece78b6a503bcb2931021bb90daef3b5567231f3f79eb5c58e`.
Declared source-snapshot SHA1: `133a96deec47fb26f5d606d2cc33868dd4cc7616`; this is **not a JJ commit revision**. Full candidate identity is separately bound by the receipt.

Preserved failures: the first accidental whole-swarm test invocation found three missing scratch fixtures (668 passed); copying the two existing repository fixtures yielded 671 passes. The first environment-link test exposed an Erlang list/binary mismatch and then passed after correction. Earlier private staging reached its configured 180-second deadline and terminated; final staging was deliberately stopped successfully. Initial staging declared an old source identifier and was retired; final identity uses its exact source snapshot. An obsolete dependency-only candidate remains non-deployable evidence.

## 8. Files Modified

- `apps/uos_swarm/src/uos_swarm/session_store.gleam` and `test/session_store_cli_test.gleam`: insert guards and falsifiers.
- `tools/km_provenance/{km_chain.ml,km_chain.mli,km_chain_test.ml,dune}`: verified transactional append, private helper, no-replace and regression target.
- `tools/ecology_release.ml`: metadata capsules, strict environment/interpreter binding, explicit non-admitted rebind and selftests.
- `apps/cepaf_gleam/src/ecology_capability_ffi.erl` and `tools/validation/ecology_capability_ffi_test.erl`: effect-time checks and regression.
- `governance/planning/20260930-0421-fractal-recovery-risk.json`, this journal and the timestamped evidence directory.
- Development build caches, new immutable package/capsule and private recovery candidates are generated artifacts.

Extensive unrelated pre-existing workspace changes remain untouched. Standalone Jujutsu is preserved; no Git mutation, integration bookmark, EV number or source-history rewrite occurred. Exact current source hashes are in [the hash inventory](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260930-0451-fractal-recovery-evidence/20260930-0451-source-hashes.txt). Builds and source snapshots do not assert a clean integrated revision.

## 9. Architectural Observations

Gleam retains coordination/control semantics; Erlang is a bounded existing filesystem/process facade; Hermes OCaml owns evidence verification; MAX remains isolated. Engine 5/sheaf-presheaf consistency: locally valid prefixes and a running ecology instance cannot be combined into global authority while history selection and live fencing remain unresolved.

All 17 release aspects were considered:

| Aspect | Scope/result and outstanding obligation |
|---|---|
| A01 hardware/storage | No drive operation; hardware interlock UNRUN |
| A02 standalone JJ | No Git mutations; empty marker preserved externally; integrated clean revision UNRUN |
| A03 Zero-Muda | No new dependency; complete historical purity scan UNRUN |
| A04 OTP supervision | Actual OTP29 private ecology startup/shutdown; four-domain failover UNRUN |
| A05 ZigVM/VFS | Kernel unchanged; eight VFS laws UNRUN |
| A06 Hermes/formal | OCaml regressions/chain verification PASS; Gospel/Z3 authority UNRUN |
| A07 mathematical authority | Digest/replay and finite falsifiers tested; global proofs UNRUN |
| A08 cybernetic authority | Evidence-only recovery retained; typed activation missing |
| A09 MAX/Mojo | Actual MAX invocation and Mojo verification PASS; full environment closure not hashed |
| A10 Zenoh mesh | Untouched; authenticated routing/replication UNRUN |
| A11 AG-UI | Full 32-event SSE conformance UNRUN |
| A12 A2UI | Component catalog unchanged; broad UI tests UNRUN |
| A13 accessibility | Browser/human acceptance UNRUN |
| A14 Tailnet navigation | FQDN private HTTP health/identity observed; remote ecology publication UNRUN |
| A15 checklist | Explicit scoped checklist below; global readiness HOLD |
| A16 KM triad | Linked evidence/journal; ontology admission UNRUN |
| A17 durable planning | Canonical RCA/REVIEW; ACTIVATE pending; live effect fence missing |

## 10. Remaining Gaps

**The live system has not been fully stabilized.** Canonical coordinator/cycle histories and the failed production ecology instance remain unchanged. Original SQLite rows, all 1,762 legacy files, and all 550 cycle rows are preserved. Prefix candidates are alternatives for explicit recovery selection, not automatic replacements.

The concrete blocker is missing typed canonical recovery activation: `session_store_cli recover-stage` is `evidence_only` and `admitted=false`; no recover-activate operation was found. Harness completion reconciliation is a different operation. Empty lsof/fuser observations do not prevent a new writer or grant ownership.

[SC-HARNESS-MCP-001](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md) requires operational intents through the harness and says the development bootstrap “grants no production admission”. [SYNC-04](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-0653-tri-agent-coordination.md) requires a typed revision-bound target, ownership, rollback and post-change check. These are explicit policy requirements, not inferred permission from a test count.

Canonical task ACTIVATE records the next gate: implement/test the missing Gleam recovery authority path, or obtain a separately explicit bounded operator recovery exception. Any eventual operation must independently select lineage, prevent writer re-entry, preserve original DB/WAL/SHM and the legacy tail, hold effects across state transitions, invalidate historical leases, acquire fresh runtime ownership, and verify every target. Recovery rollback remains a proposal until exercised under authorized state control. The prior failed ecology package is not advertised as a healthy fallback.

The environment closure beyond interpreter/metadata identity is not fully hashed. OpenRouter had no staging credential and truthfully reported unavailable. Existing EV-111 manifest claims and broader admission gaps are not repaired by this pass.

## 11. Metrics Summary

Engine 3: 671 swarm tests, seven ecology tests, 23 package selftests and 31 preflight checks passed; the 33 focused tests are a subset, not an additive count. The coordinator candidate has 1,761 events; the cycle candidate has 332 rows and 24 active holds. MAX probability differs from the independent analytic expectation by less than 0.000001.

Selected tests are correlated, not repeated production trials. No calibrated Bayesian reliability posterior, half-life decay estimate or Lyapunov dV/dt claim is made. Fresh source hashes, clock observations and exact candidate identities bound these results.

## 12. STAMP & Constitutional Alignment

Raw FMEA: S4 × O3 × Det3 = RPN36; risk class P1, ranking 960 after authority/dependency constraints. All four UCA types are recorded in the risk file: withholding repair, providing unsafe recovery, wrong-time/stale cutover, and excessive-duration/retry. Controls preserve original history and refuse false authority. No storage wipe, new package, external source mutation, production restart or EV minting occurred.

<details>
<summary>Comprehensive verification checklist — scoped evidence only</summary>

| Domain | Checkpoints and current scope |
|---|---|
| 1 metadata/navigation | CHK-01-TIME synchronized host observed; CHK-02-TAIL full FQDN links/private HTTP; CHK-03-FRACT layers mapped; CHK-04-KM full graph integration UNRUN |
| 2 purity/storage | CHK-05-MUDA no new prohibited dependency; CHK-06-GRAPH no foreign graph NIF; CHK-07-DRIVE interlock UNRUN, drives untouched |
| 3 testing | CHK-08-C1C8 full UI suite UNRUN; CHK-09-MATH four gates UNRUN; CHK-10-9MOD partial regressions/falsifiers; CHK-11-REGR scoped tests PASS |
| 4 language/observability | CHK-12-GLEAM actual OTP and typed store tests; CHK-13-HERMES bounded ledger verification; CHK-14-ZIGVM UNRUN; CHK-15-MAX actual graph PASS; CHK-16-OTEL full trace propagation UNRUN |
| 5 governance/JJ | CHK-17-SOV independent development review PASS, live admission HOLD; CHK-18-JJ standalone preserved, integration not claimed |
| 6 provenance | EV ceiling93 retained; no new EV; originals preserved; candidate integrity PASS; canonical chain/admission HOLD |

</details>

## 13. Conclusion

Engine 7 Forecast, explicitly uncalibrated: with the exact final package, unchanged realized environment and the same bounded private configuration, another startup within one hour of 04:56 UTC is expected to return running health, advancing cycles and actual MAX output within 30 seconds. A dependency mismatch, missing receipt, non-advancing cycle or failed startup falsifies it. No probability or Brier score is fabricated; calibration remains UNRUN.

Development RCA, tested repairs and independent candidate review are complete. Live restoration remains a separately tracked HOLD. This preserves the distinction between a known working private runtime and authorized production operation.

[Previous baseline](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260930-0408-stabilization-operating-baseline.md) · [Recovery receipt](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260930-0451-fractal-recovery-evidence/20260930-0451-recovery-receipt.json) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning)

UOS footer: independently reviewed development evidence is not production admission.
