# 20260909-1126 Native launch correction and reviewed producer completion

Observed UTC: **2026-09-09T11:38:26Z**. #fractal-l0 #fractal-l2 #fractal-l3 #fractal-l6 #fractal-l7 #zk-adr #zero-muda

[Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Provenance contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260908-0912-provenance-integrity-contract.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki). This private candidate has not been published or deployed.

## 1. Scope & Trigger

Continue EV-01..EV-109 evidence recovery with generated automation restricted to Gleam, OCaml or Mojo. This stage closes the native launcher and EV98 component producer repairs. The admitted ceiling stays EV-93.

## 2. Pre-State Assessment

The pinned `erl` entry point was a Bash wrapper. Earlier receipts did not establish the user's no-Bash constraint. The native adapter also leaked a reservation file and alias directory per invocation. The producer's old candidate was independently held on that launcher defect.

## 3. Execution Detail

OCaml now invokes native ERTS `erlexec`, binds ROOTDIR/BINDIR and compiler emulator selectors, and uses an owned executable alias. OCaml script drivers invoke the native `ocamlrun` directly. Parent exit removes the alias directory. Candidate fac5d6791bdf3a816294a314275960baad3ee09d received independent bounded approval after 12 adapter controls and explicit poisoned-environment checks.

The fixed producer b8da78ab9e88c5d8f41f4dc36d26f3aad3e1bc53 received independent approval after a fresh immutable build, 20 unit/process controls, 7 CLI cases, the actual 42-case runtime campaign and 3 designated compiled mutations. The review rehashed 444 bindings, 37 invocation stream sets and 128 dependency files; 170 successful traced execs across 12 paths were native ELF executables. Its Sa-plan PRODUCER task completed on attempt 2 at 11:36:18 UTC. Formal and full-mesh completion were explicitly excluded from that task result.

## 4. Root Cause Analysis

Executable names hid a shell wrapper. The original launch test checked outcome rather than actual descendant executables. A later approval wait outlasted all three one-hour task leases; queued private builds began after expiry. Those observations retain that authority caveat. The coordinator workspaces were reclaimed at new epochs, and expired Sa-plan tasks were reclaimed through the canonical lease transition, with fresh active checks before continuing. The checker preflight HOLD at expiry was not converted into a passing receipt.

## 5. Fix Taxonomy

Native executable selection, explicit process environment, interpreter bypass, temporary-resource cleanup, negative controls, independent source review, and scoped task completion. No runtime cutover or EV admission mutation occurred.

## 6. Patterns & Anti-Patterns Discovered

Trace actual process launches instead of inferring native execution from a command name. Retain wrapper-dependent evidence and failed controls. Approval-delay recovery must re-observe leases; a queued invocation is not protected by an earlier active check. The adapter continues to declare that it is not an effect-time fencing service.

## 7. Verification Matrix

| Check | Result | Scope |
|---|---|---|
| Native adapter failure and cleanup controls | 12 PASS, independently replayed | Private child processes |
| Native Gleam recovery run | 168 distinct PASS | Existing repaired components |
| Native build and runtime exec trace | ELF paths verified | Exact traced invocations only |
| Producer unit/process and CLI cases | 20 + 7 PASS | Fixed EV98 observation producer |
| Positive and mutant campaign | 42 positives + 3 designated failures | Component recipe only |
| Receipt regression suite | 67 PASS, author run | Existing receipt consistency |
| Formal/full-mesh/sovereign EV gate | NOT_ADMITTED | Required follow-up |

## 8. Files Modified

`tools/ev_native.ml`, `tools/test_ev_native.ml`, and `tools/test_session_store_verification.ml`; independently developed producer sources under `tools/ev_receipts`. This journal and its adjacent manifest preserve exact review, trace, invocation and Sa-plan completion evidence. Historical files remain unchanged.

## 9. Architectural Observations

OCaml owns bounded process execution and observation; Gleam owns runtime behavior. An interpreter or launcher path must be distinguished from its runtime executable. Native exec observations do not establish a fully reproducible OTP/shared-library closure or authenticated producer identity.

## 10. Remaining Gaps

Formal projection hardening awaits independent review. EV98 still lacks a complete tested wire transport and authentication path; a bounded lossless codec task has been created in Sa-plan. Full EV campaigns and sovereign admission are open. SIGKILL or host failure can leave private temporary directories for ordinary host cleanup. Automatic fencing immediately after delayed approval is not implemented by this adapter.

## 11. Metrics Summary

Admitted ceiling: 93. New EV numbers: 0. Completed scoped producer task: 1. Root programme: executing attempt 2. Native adapter controls: 12; combined runtime cases: 168; fixed producer positives: 42; designated mutations detected: 3. These counts are not interchangeable with admitted EV cycles.

## 12. STAMP & Constitutional Alignment

Unsafe provision: wrapper-dependent observations represented as native evidence. Omission: failed process outcomes ignored by downstream evidence readers. Wrong timing: an approval arriving after the task lease. Excessive duration: work continuing on a stale attempt. Controls preserve failures, bind current source and worker observations, isolate child processes and keep the EV ceiling unchanged. Only Sa-plan records task completion; review receipts confer no deployment authority.

## 13. Conclusion

The native launcher and fixed component producer are independently reviewed repairs. The producer task is complete within its explicit scope. EV-94..EV-109 remain NOT_ADMITTED.

## Comprehensive verification checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Observed UTC prefix and synchronized active receipts retained.
- [x] CHK-02-TAIL — Full Tailnet links provided; private candidate delivery unverified.
- [x] CHK-03-FRACT — Applicable fractal layers tagged.
- [x] CHK-04-KM — Evidence manifest and governing provenance contract linked.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- [x] CHK-05-MUDA — Authored automation is OCaml/Gleam; traced native launches reviewed.
- [ ] CHK-06-GRAPH — Fleet-wide source/dependency purity scan not rerun here.
- [ ] CHK-07-DRIVE — Hardware interlock execution outside this process-only stage.

</details>
<details><summary>Domain 3 — Testing and mathematics</summary>

- [ ] CHK-08-C1C8 — Complete release modality coverage not established.
- [ ] CHK-09-MATH — Full capability formal gate remains open.
- [x] CHK-10-9MOD — Scoped runtime and designated mutation evidence retained; full nine modalities not claimed.
- [x] CHK-11-REGR — Relevant adapter and producer regression controls passed.

</details>
<details><summary>Domain 4 — Runtime domains and observability</summary>

- [x] CHK-12-GLEAM — Actual bounded component behavior executed.
- [x] CHK-13-HERMES — OCaml receipts and source checks observed.
- [ ] CHK-14-ZIGVM — Kernel runtime revalidation outside this stage.
- [ ] CHK-15-MAX — Actual inference campaign not performed.
- [ ] CHK-16-OTEL — Full deployed trace correlation not established.

</details>
<details><summary>Domain 5 — Governance</summary>

- [ ] CHK-17-SOV — Component review complete; sovereign EV admission pending.
- [x] CHK-18-JJ — Standalone JJ sibling candidates; no canonical integration/runtime cutover.

</details>
<details><summary>Domain 6 — Provenance</summary>

EV-94..EV-109 remain NOT_ADMITTED. Historical wrapper and expired-lease observations remain explicitly limited. Review and component task completion cannot raise the admitted ceiling.

</details>

Manifest: `docs/reviews/20260909-1126-native-launch-and-producer-stage.json`. UOS evidence footer: observation and component completion only; no EV admission.
