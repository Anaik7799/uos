# 20260907-1543 — Solo5 producer and consumer source review

#fractal-l0 #fractal-l3 #fractal-l4 #zk-adr #zero-muda #tailscale-web

**UOS / Mirage / Source review** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)

**Document:** [Rendered](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1543-solo5-producer-consumer-source-review.md) · [Raw](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1543-solo5-producer-consumer-source-review.md). Canonical links are navigation; this lane did not publish these isolated artifacts.

## 1. Scope & Trigger

Review seven Solo5 producer/consumer files from immutable canonical snapshot `7634c2ae8f808bae1c7832a25a8762b1e7c33ab4`. **Not approved: source blockers remain.** This snapshot is not a quiesced AGY handoff; no final peer candidate had been supplied at review time.

## 2. Pre-State Assessment

The parent reports successful native tests and a real patched Mirage guest, but needs independent verification of the receipt boundary. Peer journal completion claims do not establish that boundary. The seven isolated source hashes exactly match the canonical observation at 2026-09-07T14:56:51Z.

## 3. Execution Detail

Used isolated JJ and verification-before-completion for bounded source inspection. Read the producer ML/interface/C stub/test, Gleam projection, CLI gate and Erlang receipt validator. Read-only SHA256/stat checks confirmed six declared Solo5 0.13.0 tender/hello-guest pins match installed files at observation time; QEMU was hashed separately. No native test, consumer reproduction or formal tool was executed.

## 4. Root Cause Analysis

The system equates asserted receipt fields with authenticated current execution. Producer, CLI and projection apply different predicates; none binds the full candidate, invocation, boot, artifacts, output completeness and cleanup context.

## 5. Fix Taxonomy

Review artifacts only. Required repair is a shared typed admission contract plus a supervised producer with explicit complete/error/overflow/timeout outcomes, exact artifact/QEMU context and unconditional cleanup. A new frozen candidate then needs independent negative controls and bound native evidence.

## 6. Patterns & Anti-Patterns Discovered

Declaring guest hashes does not verify them. Hashing after a run does not identify what ran. A timestamp prefix, digest length or self-reported review label cannot authenticate evidence. A passing leader is not proof that its process group was reaped.

## 7. Verification Matrix

| Finding | Source observation | Required correction |
|---|---|---|
| S13-01: projection provenance/freshness | `mirage_hypervisor.gleam:294` tests only prefix `2026`; type drops boot/digests; hardcoded verified fixture remains public | Preserve identity fields and validate actual time/current expected context |
| S13-02: CLI forgery acceptance | `uos_ffi.erl:103` checks boot length; `:107` permits ±7 days; `:119` checks hash length; trusts passed/review labels | Strict typed equality, authentic receipts, future rejection, bounded age |
| S13-03: incomplete artifact binding | Producer guest pins unused; fallbacks accepted; direct runner checks path/ELF/size; hashes only after run | Require exact approved tender/guest pins before and after execution |
| S13-04: QEMU identity divergence | Report uses PATH lookup; feature command hardcodes /usr/bin; virtio script uses inherited PATH; feature exit ignored | Bind one QEMU digest/path/environment and successful completion |
| S13-05: incomplete output/cleanup | Byte cap/read error treated as EOF; group cleanup only on timeout; exception paths leak cleanup; blocking final wait | Explicit failure states, total bounds and unconditional group/descriptor cleanup |
| S13-06: weak profile semantics | Parser accepts 0.12.1 and substring SUCCESS; expected-code parameter ignored | Exact release/profile/output and complete evidence |
| S13-07: stale gate artifact checks | Gate uses legacy guest paths; ELF check reads only four bytes while PASS claims ≥10KB | Use the same artifact/receipt validator and truthful output |
| S13-08: insufficient tests | Optional missing receipt passes; labels printed PASS regardless of readiness; no forgery/truncation/cleanup controls | Test missing invariants against actual repaired implementation |

[Evidence JSON](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1543-solo5-producer-consumer-source-review-evidence.json) contains detailed locations, consequences, patch guidance, exact source hashes and installed artifact observations. Findings are source deductions, not newly executed exploit or failure reproductions.

Positive source changes are real: KVM ioctl, monotonic/select loops, three-tender conjunction and stronger output token checks. Installed pins match at read time. These improvements do not close the table's obligations. The observed QEMU SHA256 is `0cd4112a8f0cb891eb7c10e8df38c9dfeec8c7389bb22db6aa425f0d6fe733dc` (31,328,048 bytes); the producer does not bind it.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] CHK-01-TIME — Host UTC 2026-09-07T15:00:43Z; NTP synchronization reported yes.
- [x] CHK-02-TAIL — Canonical navigation supplied; serving untested.
- [x] CHK-03-FRACT — Fractal/governance tags assigned.
- [ ] CHK-04-KM — Source/evidence links supplied; live transclusion unverified.

</details>
<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] CHK-05-MUDA — No dependency or imported source added.
- [x] CHK-06-GRAPH — Documentation-only change; no native kernel added.
- [ ] CHK-07-DRIVE — Hardware storage interlock outside scope.

</details>
<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI protocol unrun.
- [ ] CHK-09-MATH — Prior reference model is not implementation refinement; no formal tool rerun.
- [ ] CHK-10-9MOD — No runtime tests in this source lane.
- [ ] CHK-11-REGR — No live regression or monitoring run.

</details>
<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Projection gaps remain.
- [ ] CHK-13-HERMES — Producer completeness/cleanup gaps remain.
- [ ] CHK-14-ZIGVM — Runtime kernel outside scope.
- [ ] CHK-15-MAX — Inference outside scope.
- [ ] CHK-16-OTEL — Collector/trace propagation unrun.

</details>
<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] CHK-17-SOV — Source snapshot not approved; no admission or deployment authority.
- [x] CHK-18-JJ — Isolated JJ snapshot; owned artifacts only; no native Git or main move.

</details>

## 8. Files Modified

Added this journal and its evidence JSON. The seven reviewed implementation files remain byte-identical to the captured immutable revision.

## 9. Architectural Observations

The previously checked receipt-admission reference model at `7621d5dfebe92ed8de7684e392b92c983b3acf36` names candidate/boot/run/guest/tender/freshness/completeness/profile obligations. It does not prove this source implements them.

## 10. Remaining Gaps

All eight findings require disposition. The final peer handoff and fresh implementation negative controls remain absent from this lane. Parent-owned native successes must retain their own exact revision, artifact and invocation bindings.

## 11. Metrics Summary

Seven source files inspected; seven root/snapshot hashes agree; six installed Solo5 pin pairs match; one QEMU digest observed. Native/consumer/formal test invocations and production mutations: zero.

## 12. STAMP & Constitutional Alignment

The unsafe action is projecting current readiness from incomplete or unbound observations. A peer journal, matching installed file or reference proof cannot independently grant execution credit or deployment authority.

## 13. Conclusion

Snapshot `7634c2ae8f808bae1c7832a25a8762b1e7c33ab4` remains **not approved**. The source review is complete within its read-only scope; a repaired frozen candidate needs a new evidence decision.

**Previous:** [Peer remediation claims](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1436-solo5-0-13-0-hypervisor-probe-and-receipt-remediation-journal.md) · **Next:** [Source review evidence](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1543-solo5-producer-consumer-source-review-evidence.json)

**UOS footer:** Independent source evidence; no runtime or deployment admission.
