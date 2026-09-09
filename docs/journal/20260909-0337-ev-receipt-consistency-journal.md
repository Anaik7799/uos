# EV receipt consistency journal

Created 2026-09-09T03:35:37Z from the synchronized host clock.
#fractal-l0 #fractal-l3 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0337-ev-receipt-consistency-spec.md) · [Journal source](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0337-ev-receipt-consistency-journal.md)

## 1. Scope & Trigger

Parent programme `uos/ev-admission/20260909-0210` delegated an independent receipt validator supporting the requested EV-01..109 work. Child plan `uos/ev-receipt-validation/20260909`, task `VALIDATE`, worker `codex-ev-receipts`, attempt 1 owns the bounded source work. Success is evidence consistency and review readiness; admission authority is NONE.

## 2. Pre-State Assessment

The inherited legacy admission path trusted insufficient evidence; parent owns its repair. This workspace started at immutable commit `337f99137673d7866b958a38bd490fb876b2880f`. No receipt-validation project existed. Child workspace lease belongs to the actual parent session `01a08017-fd72-7b20-9d32-4df53154bcc8`, epoch 1, coordinator sequence 1185. No fabricated Herdr session was registered.

## 3. Execution Detail

Created an isolated Jujutsu workspace, registered and claimed the exact child task through Sa-plan after preflight, and observed active worker/attempt through the risk checker. Chrony required host-access escalation; the original sandbox HOLD was not treated as a pass. Implemented an independent OCaml/Dune project with strict JSON schemas, byte digests, bounded read-only Jujutsu source comparison, process limits, clock observations and negative controls. Existing repository OCaml/Yojson/Cryptokit/Unix/Mtime tools were used; no packages were provisioned.

## 4. Root Cause Analysis

A digest-shaped string or matching revision labels do not show that cited bytes exist at that candidate. Conversely, internally consistent JSON does not authenticate a producer or prove that a claimed invocation ran. These are distinct gaps. The reader closes the byte/revision consistency gap, while exposing the authenticity and semantics gap for independent review instead of granting authority.

## 5. Fix Taxonomy

Input validation rejects schema, type, coverage, key duplication, time and status errors. Filesystem validation rejects nonregular inputs, symlinks, traversal and ordinary concurrent changes. Independent source observation compares actual immutable Jujutsu bytes. Resource controls bound parsing, input sizes, subprocess duration and output. Output semantics explicitly limit success to `EVIDENCE_CONSISTENT`, authority NONE.

## 6. Patterns & Anti-Patterns Discovered

The initial permissive scaffold accepted 37 invalid fixtures, providing observed red tests before implementation. A clock scaffold accepted five invalid host-clock observations. A later positive test exposed overstrict rejection of repeated argv entries; command arrays now permit repetition while coverage and identity sets stay unique. Synthetic positive fixtures deliberately remain acceptable for consistency, preventing an unsupported claim of producer authentication.

## 7. Verification Matrix

| Observation | Result | Actual scope |
|---|---|---|
| Initial receipt scaffold | 37 failures / 38 cases | Preserved expected red output |
| Clock scaffold | 5 failures / 6 clock cases | Preserved expected red output |
| Repeated argv positive | Failed before repair | Preserved expected red output |
| Native build | Exit 0 | Existing repository compiler/libraries |
| Receipt, file and process checks | 50 cases passed | Synthetic receipts, genuine immutable source reads |
| Host-clock parser | 6 cases passed | Valid, malformed, unsynchronized, nonfinite, future and stale observations |
| Actual CLI synthetic bundle | EVIDENCE_CONSISTENT; authority NONE | Real chrony and immutable source observation; synthetic producer claims |
| Formal proof / independent review | UNRUN / pending | No system or capability admission claimed |

Final machine receipts bind source hashes and immutable tested revision separately from this explanatory journal. The passing CLI observation cannot be promoted into an EV admission receipt.

## 8. Files Modified

New files only: `tools/ev_receipts/{.gitignore,dune,dune-project,receipt_validator.ml,ev_receipt.ml,receipt_test.ml}`; this timestamped journal and linked specification; timestamped risk assessments and observed test receipts under `docs/reviews`. Parent-owned legacy admission, ledger, Mojo, runtime and historical files are untouched.

## 9. Architectural Observations

The implementation is native bounded OCaml analysis. It introduces no persistent service, scheduler, control-plane mutation or live database writer. It does not read or append an admission table. Root programme integration with legacy gate entrypoints remains separately owned and reviewed.

## 10. Remaining Gaps

Receipt authenticity, actual runtime execution, verifier semantics, acceptance completeness, trusted toolchain producers, source scope completeness and sovereign review remain external obligations. Cooperative file checks do not defeat hostile same-UID races. No formal refinement theorem is supplied. Expensive source manifests may hit the fixed reader deadline and HOLD rather than receiving clearance. Task remains executing until parent review; no autonomous completion or integration is asserted.

## 11. Metrics Summary

56 observed passing tests after repairs, with earlier failures preserved. Limits include 1 MiB per input, 16 MiB aggregate reads, 128 source entries, 32 JSON depth, 5-second Jujutsu readers, 3-second host-clock readers and a 120-second validation-stage deadline. No new package or paid inference consumption. The specification gives exact limits and interpretation.

## 12. STAMP & Constitutional Alignment

All four UCA types are addressed: required evidence omitted; unsafe evidence supplied; observation bound to wrong revision/time; and reads exceeding duration/ownership. FMEA false admission remains severity 5; tested consistency controls do not justify lowering the residual authenticity risk. P1 repair is authorized independently of downstream admission. Sa-plan and separate workspace fencing remain effect authority, while risk-check PASS is only an observation.

## 13. Conclusion

The bounded validator is ready for independent source review and integration assessment, with synthetic test receipts and honest authority limits. No EV number was minted, no admitted ceiling changed, and no historical evidence was rewritten. Root programme must obtain and review authentic runtime/formal evidence before any supported admission action.

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
