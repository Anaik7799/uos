# SQLite verification and EV98 replay repair

Observed: 2026-09-09T05:35:12Z. Source candidates: SQLite `e2bb27072c55128420d529533686a86e896dec62`; EV98 `4af745383248649d0472b734ab825702ee490def`.

#fractal-l0 #fractal-l2 #fractal-l3 #fractal-l4 #zk-adr #zero-muda #checklist-nav

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [Observed receipts](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-0512-sqlite-and-ev98-repair-observations.json)

## 1. Scope & Trigger

Continue the authorized EV01–109 programme in its isolated JJ workspace, using Gleam and OCaml code and native argv execution. Repair verification gates and EV98 replay behavior before recording bounded task completion. PROGRAM remains executing; no new EV number or admission is issued.

## 2. Pre-State Assessment

The active coordinator uses the file-journal CLI. Private SQLite execution now works with realized Gleam 1.16.0 and OTP29, but a corrupted store returned exit0 and verification initialized absent paths or restored missing triggers. EV98 originally passed32 tests yet lost the latest health value on reverse replay of equal-time samples. RAG tests also passed before independent freshness and numeric probes exposed defects.

## 3. Execution Detail

SQLite verification opens an existing percent-encoded absolute path in read-only mode, holds one read transaction, checks metadata without DDL, compares required trigger definitions, and derives JSON and nonzero process status from a typed failure. New OCaml orchestration executes synthetic fixtures only. Independent source checks bound70 staged entries and four driver files to the immutable candidate. EV98 now orders physical health observation time before logical version and writer identity, retains accepted observation watermarks, and preserves FIFO queue refusal and retained-state dead-man behavior. Its REPAIR task completed through Sa-plan attempt1 after independent approval and a fresh active check at05:27:00Z.

## 4. Root Cause Analysis

SQLite reused a create-and-repair connection path for inspection and treated serialization of a failed report as command success. Trigger-name counting accepted weakened guards. Private file-copy and byte tests were unstable because esqlite query statements await garbage collection and close_v2 may defer final closing and WAL checkpointing. EV98 combined equal-version health replacement with a newer vector clock, preventing anti-entropy from requesting the lost update.

## 5. Fix Taxonomy

Inspection and initialization now have separate paths; failure status and failure JSON share a typed result; exact trigger definitions replace name-only trust. Private test writers checkpoint before copying or comparing main-file bytes. This fixture repair does not relax production checks. EV98 uses a deterministic health order with explicit physical and logical time and retains accepted gossip/incoming time.

## 6. Patterns & Anti-Patterns Discovered

Inspection must not repair the evidence it judges. Successful JSON generation does not mean the reported check succeeded. A causally advanced digest cannot recover a value discarded by an inconsistent merge order. Tests need adversarial sequence and boundary cases: RAG original tests missed future observations, stale refreshes, dimension mismatches, overflow and tiny-vector precision failures. All observed failures remain evidence.

## 7. Verification Matrix

| Observation | Actual result | Limit |
|---|---|---|
| SQLite component cases |20 passed independently|Private synthetic stores|
| SQLite CLI process cases |6 passed independently|Corrupt/absent/empty cases require exit1|
| Additional SQLite probes |3 passed independently|Old schema, literal URI/Unicode paths, weakened guard|
| Native adapter regressions |6 passed independently|Private child effects and reporting behavior|
| EV98 focused cases |42 passed independently|Serialized retained state|
| EV98 ordered and associative checks |324 +5832 passed|Finite18-state domain, not an unbounded proof|
| RAG independent review |HOLD at last recorded review|Numeric follow-up still active|
| Full EV admission |NOT_GRANTED|Runtime/formal/sovereign closure remains open|

The build retains existing Erlang FFI/compiler warnings. The initial new test return-type error and private fixture failure are preserved. The author green run preceded final formatting; the independent fresh run binds the final immutable bytes.

## 8. Files Modified

SQLite changes are in `session_store.gleam`, `session_store_cli.gleam`, the new Gleam verification tests and one existing fixture checkpoint. `ev_native.ml` adds literal CLI arguments after OTP `-extra`; `test_session_store_verification.ml` provides bounded native orchestration. EV98 changes and journals reside in its reviewed source/evidence parents. Timestamped observations preserve independent reports and actual invocation receipts.

## 9. Architectural Observations

SQLite native readiness is now observed; live coordinator cutover is a separate unfinished operation. Producer identity, full event semantic replay and complete schema authenticity are beyond this structural verifier. SQLite may manage reader sidecars even though the inspection connection cannot change database rows or schema. No connection or board ACK grants integration, runtime or admission authority.

## 10. Remaining Gaps

The live cutover still needs a pinned database/launcher/writer transition, current fences, writer quiescence, an approved migration source, replay comparison, concurrency/crash/busy/I/O/durability recovery evidence and observation of the actual switch. EV98 needs live transport, mixed-version compatibility, authenticated identities, durable recovery and formal refinement. RAG review remains active. The wider EV programme and manual acceptance remain incomplete.

## 11. Metrics Summary

One bounded EV98 repair task completed; PROGRAM remains executing. The policy ceiling stays93 and new admissions remain0. Test counts describe executed cases and are not an EV completion percentage.

## 12. STAMP & Constitutional Alignment

False admission remains the programme's S5/O3/Det4 risk, RPN60. The four UCA classes are missing checks, unsafe success reports, stale/reordered observations, and effects outlasting their safe bounds. Risk checks passed for the scoped root and EV98 source at05:27:00Z with actual Sa-plan workers/attempts. JJ source/evidence history and failures are preserved. No live ledger rewrite, external-source mutation or deployment occurred. Release aspects explicitly covered: scope, authority, source, build, regression, finite properties, formal limits, local runtime, OTP/ERTS, dependency limits, security, storage, observability, bounded performance, scalability limits, recovery limits and independent review.

## 13. Conclusion

The SQLite verification repair and EV98 state repair have independent bounded approval. The full EV programme remains active and admission is not granted by these observations.

## Comprehensive verification checklist

<details><summary>Domain 1 — Metadata, timestamp and navigation</summary>

- [x] CHK-01-TIME — Host-derived timestamp; observed active-check clock recorded.
- [x] CHK-02-TAIL — Full Tailscale references supplied; live publication remains unverified.
- [x] CHK-03-FRACT — Fractal tags supplied.
- [x] CHK-04-KM — Source, observations and historical context referenced.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- [ ] CHK-05-MUDA — Full production dependency scan remains required.
- [ ] CHK-06-GRAPH — Real graph execution boundary remains required.
- [ ] CHK-07-DRIVE — Live storage interlock acceptance remains required.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI acceptance remains required.
- [ ] CHK-09-MATH — Four system mathematical gates remain required.
- [ ] CHK-10-9MOD — Focused suites do not cover every modality.
- [ ] CHK-11-REGR — Full system regression and monitoring remain required.

</details>
<details><summary>Domain 4 — Runtime and observability</summary>

- [ ] CHK-12-GLEAM — Operational supervision and recovery still need evidence.
- [ ] CHK-13-HERMES — Formal authority and live coordinator cutover remain open.
- [ ] CHK-14-ZIGVM — Current deterministic runtime/VFS acceptance remains required.
- [ ] CHK-15-MAX — Actual supervised inference remains required.
- [ ] CHK-16-OTEL — End-to-end operational traces remain required.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Full sovereign admission has not been granted.
- [x] CHK-18-JJ — Isolated JJ candidates preserved; no native Git mutation.

</details>
<details><summary>Domain 6 — Provenance</summary>

EV-94 through EV-109 remain NOT_ADMITTED. Historical corruption and inconsistent scope claims remain recorded. No component test count or board message substitutes for candidate-bound admission.

</details>

**Previous:** [Recovery progress](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0344-ev-admission-recovery-progress.md) · **Next:** [Planning](http://nas-1.tail55d152.ts.net:4100/planning)

**UOS footer:** Isolated development evidence; live publication and EV admission not granted.
