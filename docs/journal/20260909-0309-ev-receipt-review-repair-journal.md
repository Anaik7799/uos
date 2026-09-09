# EV receipt validator independent-review repairs

Created 2026-09-09T03:57:09Z from the observed host clock.
#fractal-l0 #fractal-l3 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0337-ev-receipt-consistency-spec.md) · [Earlier journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0337-ev-receipt-consistency-journal.md)

## 1. Scope & Trigger

Independent parent review held candidate `0c2b1c4e17c67267bd044e0089cbfed05324f928`: a hexadecimal revision was treated as a configurable Jujutsu revset symbol; final chrony latency could cross evidence expiry; aggregate read and duration claims omitted work. The reviewer also required explicit caller-selected policy limitations. These repairs remain within Sa-plan `uos/ev-receipt-validation/20260909`, task `VALIDATE`, worker `codex-ev-receipts`, attempt 1.

## 2. Pre-State Assessment

The prior 56 passing tests did not cover those cases. Both prior immutable candidates and their receipts remain preserved. Fresh pre-repair risk observation passed at 03:49:58 UTC. Parent renewed workspace epoch 1 under actual session `01a08017-fd72-7b20-9d32-4df53154bcc8`, sequence 1198, operation `renew-ev-receipt-validation-20260909-0346`.

## 3. Execution Detail

Observed the conflicting-symbol regression fail using only a child-process `JJ_CONFIG` fixture. Added `commit_id("FULLHEX")` selection and exact resolved `self.commit_id()` equality. Observed four boundary scaffold failures before adding final expiry checks and shared byte/time accounting. The operator then explicitly prohibited Bash; subsequent build/test orchestration uses OCaml and direct native executables only. No persistent shared configuration was changed.

## 4. Root Cause Analysis

Syntax validity was incorrectly conflated with an immutable revision selector. Time validity was checked inside the library before a later CLI effect. The old resource counter measured initial local reads while documentation described a broader aggregate. These are separate observation-to-use and accounting defects; fixing one does not establish the others.

## 5. Fix Taxonomy

Revision selection now uses an explicit function and verifies the actual returned full commit ID. The library returns `valid_until`; the CLI's finalization checks final UTC and monotonic progression against it after chrony. One shared budget charges local bodies, Jujutsu stdout and final rehashes, and limits each of the three Jujutsu phases by remaining time and bytes. Explicit output/spec limitations cover caller-selected policy identity and cooperative filesystem/kernel return.

## 6. Patterns & Anti-Patterns Discovered

A full-length hexadecimal label can still be an alias in a configurable selector language. A successful inner validator can become stale before outer reporting. Aggregate limits must follow every read path, including rechecks. Tests for the resource fixes now assert specific rejection reasons, so unrelated fixture defects cannot masquerade as quota enforcement.

## 7. Verification Matrix

| Check | Observation | Scope |
|---|---|---|
| Conflicting symbol alias | Failed before repair; passed afterward | Native Jujutsu with isolated child configuration |
| Final clock crosses expiry | Failed against scaffold; passed afterward | Deterministic final-time boundary, no sleeping |
| Nonfinite final clock | Failed against scaffold; passed afterward | Output validity |
| Aggregate counter and staged deadline | Failed against scaffolds; passed afterward | Shared budget controls |
| Actual final rehash of large fixture | Refused with `aggregate content byte quota` | 8 MiB initial output bodies plus rehash work |
| Actual Jujutsu metadata exhausts byte budget | Refused with `reader budget exhausted` | Content phase cannot begin |
| Deadline after actual Jujutsu metadata | Refused with `validation deadline` | Deterministic monotonic observation, real metadata process |
| Complete revised test suite | 66 passed, 0 failed | 56 prior cases plus 10 review cases |
| Sovereign admission | Not granted | No authentic producer or formal semantics claim |

Final source-bound receipts are recorded separately after freezing the repair source. Earlier green and red artifacts are unchanged.

## 8. Files Modified

Changed the three native OCaml files `receipt_validator.ml`, `ev_receipt.ml`, and `receipt_test.ml` in `tools/ev_receipts`, revised the timestamped specification, and added this journal plus timestamped risk/test/review receipts. No live database, historical ledger, runtime, or parent-owned legacy source was changed.

## 9. Architectural Observations

The reader still has no authority or write path for admission. Source consistency depends on explicit Jujutsu commit semantics; policy identity, applicability and completeness are separate sovereign obligations. The public library is an observation mechanism; the CLI owns the final-clock boundary before reporting.

## 10. Remaining Gaps

Local filesystem/kernel calls and child reaping require cooperative OS return; the checked 120-second deadline is not a hard real-time guarantee. Host clock reads have separate per-observation quotas, and a rejected stdout read can observe one extra bounded chunk. Producer authenticity, proof semantics, actual execution and policy applicability remain unresolved by this reader. Independent re-review is pending.

## 11. Metrics Summary

66 passing cases; five newly observed red cases across alias and boundary scaffolds; no new packages or paid inference. Shared accepted-content quota remains 16 MiB. Candidate file observation comprises three subprocesses, each limited to five seconds and further limited by the shared remaining budget. Final validity is checked after the final host-clock observation.

## 12. STAMP & Constitutional Alignment

Unsafe evidence selection, stale output publication and unaccounted reader duration are addressed through explicit selector identity, final effect-time checks and comprehensive accounting. Severity of false admission remains 5; passing consistency checks cannot lower the unmeasured authenticity risk. Canonical Sa-plan and the separate workspace fence remain active; no review ACK is promoted into admission authority.

## 13. Conclusion

The review findings have targeted repairs and executable regression evidence. The prior candidates remain historical evidence, and the new source awaits independent re-review. `EVIDENCE_CONSISTENT` with authority `NONE` remains the strongest successful result.

## Comprehensive verification checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Synchronized host observation recorded.
- [x] CHK-02-TAIL — Full Tailnet navigation links supplied; live rendering unverified.
- [x] CHK-03-FRACT — L0/L3 scope tagged; other layers are consumers, not implemented here.
- [x] CHK-04-KM — Specification and journal linked; no new ADR or EV minted.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [x] CHK-05-MUDA — Existing OCaml dependencies only; no new packages.
- [x] CHK-06-GRAPH — Native bounded reader; no new NIF or runtime role.
- [ ] CHK-07-DRIVE — Storage interlock execution UNRUN; no storage control change.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [x] CHK-08-C1C8 — Applicable parser, filesystem, timing and negative-control cases executed; full UI categories N/A.
- [ ] CHK-09-MATH — Formal refinement proof UNRUN; report-field checks confer no mathematical authority.
- [ ] CHK-10-9MOD — Fleet-wide nine modalities UNRUN.
- [ ] CHK-11-REGR — Live UI regression N/A to this read-only CLI.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Runtime supervision UNRUN; unchanged.
- [x] CHK-13-HERMES — Native OCaml bounded analysis; no scheduler authority.
- [ ] CHK-14-ZIGVM — Kernel execution UNRUN; unchanged.
- [ ] CHK-15-MAX — Inference execution UNRUN; unchanged.
- [ ] CHK-16-OTEL — Production telemetry UNRUN; CLI reports evidence identity only.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review pending; admission NOT_GRANTED.
- [x] CHK-18-JJ — Isolated Jujutsu workspace and canonical Sa-plan worker/attempt used.

</details>
<details><summary>Domain 6 — Provenance</summary>

- [x] Synthetic receipts cannot grant admission; actual candidate source equality is distinguished from producer authenticity.
- [x] EV-93 ceiling preserved; EV-94..109 remain subject to separate sovereign review.

</details>

UOS footer: consistency observation only; canonical execution authority remains Sa-plan.
