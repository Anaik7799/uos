
Observed capture: 2026-09-09T05:00:41Z

Source candidate: `6630495091b4e2c8baa1853a99a6d30c8e5258f7`

[Machine observations](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260909-0541-ev-recovery-observations.json)

# EV admission recovery: native verification and independent review

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l6 #zk-adr #zero-muda #checklist-nav

UOS / Verification / EV recovery · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

## 1. Scope & Trigger

Continue the existing EV-01 through EV-109 programme under canonical Sa-plan authority. The operator requires Gleam, OCaml or Mojo for generated automation, with no Bash. This stage replaces wrapper-based orchestration, repairs reviewed failures, and composes independently reviewed source in an isolated JJ workspace. It does not complete the whole programme.

## 2. Pre-State Assessment

The policy ceiling remains EV-93; EV-94 through EV-109 remain NOT_ADMITTED. Earlier root work had contained file-reference admission, SQLite REPLACE bypasses and unsupported Mojo verification claims. Dispatch still equated a payload filter with DMC verification and an acquired temporal fence. Scheduler, control bounds and receipt validation had concrete independent-review findings. No candidate-bound admission was established.

## 3. Execution Detail

Native OCaml orchestration now selects the actual canonical Sa-plan database explicitly and invokes pinned tool entrypoints by argv. Gleam test mains replace handwritten Erlang evaluation. Mojo receives its required environment directly. Sa-plan BOUNDS, VALIDATE and scheduler REPAIR were completed only after scoped reviews and current active checks; PROGRAM remains executing. The four reviewed candidates were composed privately without conflicts. Fresh builds and focused executions were bound to the resulting source candidate and byte manifests.

## 4. Root Cause Analysis

The dispatch CLI trusted overlapping mode flags, and the filter reported authority it never acquired. Work transfer did not reserve receiver capacity and could confuse a rejected request with another accepted transfer. Receipt validation trusted ambiguous revision syntax and separated resource/freshness accounting across phases. Automation initially opened receipt files after execution and conflated reporting failure with child failure. These were distinct observed defects, preserved as failed observations before repair.

## 5. Fix Taxonomy

Dispatch uses a closed command grammar, a bounded exact-byte reader and explicit authority NONE. Scheduler state retains full task identities, reserves capacity and represents rejected transfers separately. Control state has bounded pending proposals, exact retirement and time-correct refill/derivative rules. Receipt validation binds explicit immutable revisions, root-relative filesets and shared final budgets. Native reporting attempts receipt persistence and output delivery independently, preserving the child outcome and an explicit post-execution failure classification.

## 6. Patterns & Anti-Patterns Discovered

Finite examples and source hashes are useful within their scope; neither authenticates a producer nor proves operational refinement. Reserving a resource must precede the irreversible half of a protocol. A wrapper default can silently select a different database. Failed output delivery does not imply that an effect did not happen. Earlier observations retain their original invocation provenance after a new language instruction.

## 7. Verification Matrix

| Executed observation | Result | Practical limit |
|---|---|---|
| Combined Gleam runner | 107 passed | Selected component and actor cases; no physical mesh or browser acceptance |
| OCaml receipt validator | 67 passed | Synthetic structural consistency; no authenticated producer or formal semantics |
| OCaml dispatch | 18 passed | Filter and command grammar; real authority adapter absent |
| Native adapter | 6 passed, independently rerun | Private child effects, receipt conflicts, signal, timeout, output bounds and broken stdout |
| Legacy admission gate | 17 passed | Invalid evidence cannot admit; no positive sovereign admission path |
| SQLite append-only defenses | 5 passed | In-memory tables only; live schema unchanged |
| Mojo component examples | 1,115 passed | Finite local examples; no formal or runtime enforcement claim |
| Mojo auto-test / deployment modes | HOLD, exit 2 | Required integration observations remain UNRUN |
| Reused dependency artifacts | 293 unchanged | Artifact equality; no reproducible source-build provenance implied |
| Source manifest | 34 files rechecked | Scoped equality, not source completeness for all EVs |

The combined Gleam build retains existing unused-import and legacy FFI warnings. A clean-environment link initially failed to find GMP. The already-installed compiler linker paths are now recorded; no package was installed. The repository-pinned release risk-checker output was queried and is not realized. Two incorrectly split Mojo mode names were refused with exit 1; corrected mode invocations are separately preserved.

## 8. Files Modified

Production source changes are the reviewed Gleam scheduler, transfer, quorum and homeostasis modules; OCaml dispatch, admission gate and receipt validator; and the Mojo runner. New automation is `tools/ev_native.ml`, its OCaml test driver/child, and the OCaml-generated `ev_recovery_runner.gleam`. Timestamped review and observation artifacts accompany the source. Historical events, live database contents, external source trees and runtime services were not rewritten or deployed by this stage.

## 9. Architectural Observations

The live runbook coordinator still uses `session_sync_cli` and the file journal. The 20260907-2250 SQLite journal explicitly records source integration and private rehearsal, with no live cutover and six then-failing tests. That historical result cannot establish current SQLite coordinator enforcement. A bounded private readiness investigation is active; no migration or backend switch has been attempted here. Sa-plan task execution uses its actual canonical SQLite database.

## 10. Remaining Gaps

EV-98 delta/freshness and EV-103 RAG freshness are separate active repairs. Authenticated actor identity, durable runtime effects, operational transport, current formal refinement, full UI acceptance and the wider 109-EV obligations remain open. AGY proposed resolving EV-01 through EV-05 to the foundational substrate and gave an EV-86 scope proposal; precise source and raw evidence references remain subject to review. No ceiling change, new EV identifier, live ledger migration or system admission follows from this stage.

## 11. Metrics Summary

Three bounded child tasks were closed through current Sa-plan attempts: BOUNDS, VALIDATE and scheduler REPAIR. PROGRAM remains executing. Independent reviews observed 400 refill combinations, 28 scheduler cases, seven receipt probes and six native adapter cases. Counts are not aggregated into an EV completion percentage. The declared admitted ceiling is unchanged; this programme has established zero new EV admissions.

## 12. STAMP & Constitutional Alignment

Raw FMEA remains S5/O3/Det4 for false admission, RPN60, in the current risk assessments. All four UCA types remain explicit: omitted evidence, unsafe authority claims, stale ordering, and operations exceeding time/resource bounds. Fresh active checks were observed before completion and source freezing. Wrong database defaults, missing attempt arguments, stale heartbeat refusals, invalid mode calls and failed builds were preserved and repaired without force-pass.

| Release aspect | Evidence state |
|---|---|
| Scope | Existing 109-EV inventory; selected component repairs verified |
| Authority | Canonical Sa-plan, current attempts; no admission authority from reviews |
| Source | Immutable JJ parents and combined candidate |
| Build | Fresh native component builds; existing warnings recorded |
| Unit/regression | Focused executed suites |
| Property | Finite control and protocol cases |
| Formal | System refinement and producer authenticity open |
| Runtime | Local probes only; live services unchanged |
| OTP/ERTS | Pinned OTP29/ERTS17.0.5 used |
| Dependencies | Existing byte inventory; full pinned release closure open |
| Security | Filter authority removed; workload authentication open |
| Storage | In-memory append-only falsifiers; no live cutover |
| Observability | Invocation outputs, hashes, clocks and limits recorded |
| Performance | Bounded probe deadlines and output quotas only |
| Scalability | No fleet-scale execution evidence |
| Recovery | Immutable candidates and failures preserved; live recovery unrun |
| Sovereign review | Bounded independent reviews; full admission ungranted |

## 13. Conclusion

The reviewed recovery components now execute together under native orchestration. The evidence supports those bounded repairs. The EV programme remains active and full admission remains NOT_GRANTED.

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
