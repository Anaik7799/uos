# 20260907-1256 — Independent MirageOS / Solo5 tender review

#fractal-l0 #fractal-l2 #fractal-l4 #zk-adr #zero-muda #tailscale-web

[Mirage cockpit](http://nas-1.tail55d152.ts.net:4100/mirage) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Machine evidence](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1256-mirage-solo5-review-evidence.json)

**Verdict: CHANGES REQUIRED for candidate `b64532f327fc5d66db60a36311d50044749083de`.**
Physical host tests succeeded at the recorded times. The candidate's gate and observation implementation do not justify continuing verification or production admission.

Document time source: observed host UTC **2026-09-07T12:48:56Z**, giving canonical prefix `20260907-1256-` (hour and seconds). Chrony sample at 12:46:30Z: system 0.000687654 seconds slow; reference 12:36:09Z; leap Normal. This is one host observation, not a claim that every agent clock is synchronized.

Owner: Codex session `01a07a68-b3b7-70f3-9e64-fac68a156c21`. Independent bounded subreview: `/root/mirage_receipt_review`, explicitly requested `gpt-6-astra` / max. Task lease: `MIRAGE-TENDERS-REVIEW`, epoch 1. The evidence JSON includes actual output, hashes and per-run times. These documents require integration before their canonical file-view links become live; the five tested endpoint links below were already live.

## 1. Scope & Trigger

The operator requested an independent check of MirageOS/Solo5 design, implementation and truthfulness at implementation `aef028b715a2f876d5027a0a81070d24b0d652f9` and journal candidate `b64532f327fc5d66db60a36311d50044749083de`, stacked on `a9d40c6e63696f16ca0c83d5512636be5a16ff1c`.

The review covered Hermes probe/runner/tests, Gleam projection and Mirage tests, Wisp endpoints, Lustre claims, TUI consistency, tools/uos tender gates, physical hello/time/stack-protection executions, artifact placement and live runtime identity. The stack also contains unrelated forecasting/MCP changes; those are not approved by this Mirage review. The broader [21-service/17-aspect design](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-1113-uos-agentic-infrastructure-reuse-and-placement.md) remains applicable. The OIDC implementation slice was left empty in its isolated workspace and its lease released when this operator review took priority.

## 2. Pre-State Assessment

A dedicated Jujutsu workspace pinned the exact candidate for all source builds and tests. Main and shared runtime code were not changed. The review documents are carried by a separate change based on `a9d40c6e`, so accepting these documents does not require importing the rejected tender implementation.

Five initial ELFs existed in canonical `var/mirage/unikernels/`; no receipt/log files were found in that directory during the initial inventory. AGY later supplied the original Solo5 source/build locator and staged three SSP ELFs. The reviewer compared their digests with the named source-build artifacts and observed equality. This establishes file identity at inspection, not independent build reproducibility.

Preflight observed approximately 830 GiB available on the workspace volume, 17 GiB free in /tmp and 32,837 MiB available RAM. Test guests had no configured network or block devices. Physical tests used external 12-second process-group deadlines with a 2-second kill grace; no production service was restarted.

## 3. Execution Detail

Eight scoped physical checks ran on nas-1. Normal hello invocations supplied the expected `Hello_Solo5` argument; virtio explicitly selected `-H kvm`. HVT strace recorded `KVM_GET_API_VERSION = 12`, `KVM_CREATE_VM` and `KVM_RUN`. SPT strace recorded successful `PR_SET_NO_NEW_PRIVS` and `SECCOMP_SET_MODE_FILTER`. QEMU strace separately recorded KVM creation and execution.

| Test profile | HVT result | SPT result | Virtio/QEMU-KVM result |
|---|---|---|---|
| Hello / expected command line | Exit 0; SUCCESS and solo5_exit(0) | Exit 0; SUCCESS and solo5_exit(0) | Exit 83; SUCCESS and solo5_exit(0) |
| Time / five one-second sleeps | Exit 0; SUCCESS | Exit 0; SUCCESS | Not run |
| SSP / deliberate guest stack corruption | Exit 255; expected stack-corruption ABORT | Exit 255; expected stack-corruption ABORT | Exit 83; expected stack-corruption ABORT |

Hello/time runs occurred 12:40:10.995239474Z–12:40:22.016148180Z. SSP runs occurred 12:47:41.777196575Z–12:47:42.220918072Z. SSP aborts are expected negative-test outcomes, not ordinary application success.

The same virtio hello ELF with an incorrect command line still returned 83 and omitted SUCCESS. Moreover, SSP's deliberate abort also returned 83. Upstream Solo5 0.12.1 ignores the guest status in this exit path and writes 41 to QEMU's debug-exit device: `(41 << 1) | 1 = 83`. The submitted journal's `(0 << 1) | 1` explanation is incorrect. [Pinned Solo5 exit implementation](https://github.com/Solo5/solo5/blob/v0.12.1/bindings/virtio/platform.c), [hello test predicate](https://github.com/Solo5/solo5/blob/v0.12.1/tests/test_hello/test_hello.c).

Candidate builds used the explicit Nix OTP 29.0.6 toolchain. Dune ran five targets, including six runner selfchecks. All four focused Mirage EUnit modules passed 24 tests; web passed 12 and tools/uos passed 14. Existing compiler deprecation/empty-module warnings were emitted, so a blanket zero-warning claim was not reproduced.

## 4. Root Cause Analysis

All source positions below refer to the frozen candidate, which can be retrieved with `jj file show -r b64532f3 <path>`.

| ID | Severity | Finding and concrete evidence |
|---|---|---|
| MR-01 | P1 | `tools/uos/src/main.gleam:348,1673`: gate and selfcheck test eight paths with file_exists. Eight zero-byte placeholders caused both to exit 0 and print physical execution/KVM/seccomp verification. No receipt content was read. |
| MR-02 | P1 | `services/mirage_hypervisor.gleam:61` returns fixed host/time and three passing receipts; `ui/wisp/mirage_api.gleam:148` serializes it directly. Live response matched the constant timestamp 12:21:04Z. Cockpit lines 45–49 also hard-code 3/3 verified. |
| MR-03 | P1 | `mirage_hypervisor_probe.ml:88,101`: PWD-derived paths are interpolated into a shell command. An existing empty image under a directory named `inject; true #` turned the trusted `/usr/bin/false` fixture into a recorded exit 0 and passed=true. |
| MR-04 | P1 | Probe lines 103–113 block on input_line and close_process_in with no timeout, output-byte bound or process-tree cleanup. A sleep-5 fixture required an external 1-second timeout, exit 124. A 20-line limit does not bound line length or wall time. |
| MR-05 | P1 | Probe lines 115,130 accept only an expected process exit code. /usr/bin/true plus an empty image produced passed=true and empty output. Real virtio wrong-argument and SSP-abort runs demonstrate that 83 alone cannot identify guest success. |
| MR-06 | P2 | Probe line 149 aggregates HVT and SPT only; virtio can be absent or failed without preventing TENDERS_VERIFIED_PHYSICAL_EXECUTION. |
| MR-07 | P2 | `test_mirage_hypervisor.ml:6–22` asserts schema, a policy string and JSON length. With PATH=/nonexistent it printed hypervisor_unavailable and “ALL HYPERVISOR PROBE CHECKS PASSED”, exit 0. Gleam's hypervisor test asserts the static success report. |
| MR-08 | P1 | Live port 4100 listener PID 3117652 used `/usr/lib/erlang/erts-15.2.7.4/bin/beam.smp`, from host OTP 27. The UI labels it OTP 29. Passing isolated OTP 29 tests does not change the running service. |
| MR-09 | P2, inherited | Probe lines 69–70 assign Some 12 after opening /dev/kvm; no ioctl is made despite the comment. This review independently observed the real ioctl returning 12, but the implementation must stop synthesizing that measurement. |

Execution receipts currently contain only tender/path, exit code, snippet and boolean. They omit executable/image digests, source/candidate revision, build identity, invocation ID, host boot identity, per-run start/end and freshness policy. The 200-character snippet truncation can omit the actual result marker. Thus the physical tests are credible observations made by this review, while the program's exported “receipts” remain insufficient.

## 5. Fix Taxonomy

**Immediate correctness:** replace the file-presence pass with fail-closed receipt validation; replace default verified projections with unknown until a valid observation exists; include all required targets in aggregate status; parse explicit per-test outcomes.

**Execution safety:** use argv-based process creation under OTP ownership, confined artifact paths, byte and duration limits, process-group termination and reaping, explicit timeout/truncation/error outcomes, and no shell interpolation. Keep Hermes' deterministic receipt/schema/oracle work separate from OTP lifecycle authority.

**Operational truth:** report actual running OTP version, observed host/boot and observation age. Use a separately authorized deployment to meet OTP 29; a board ACK is not deployment authority.

**Evidence quality:** preserve pinned source/build/artifact identities and complete bounded output digests; exercise independent negative controls. Generic library tests or declarations cannot stand in for candidate-specific formal conformance.

## 6. Patterns & Anti-Patterns Discovered

The useful pattern is test-profile-specific evidence: hello requires an exact success marker, while SSP requires an expected abort. Exit status is one observation, not the verdict. HVT/SPT are tenders; virtio here is a target launched through a QEMU wrapper, so “three verified execution targets” is the more precise description. [Solo5 architecture](https://github.com/Solo5/solo5/blob/v0.12.1/docs/architecture.md).

The regressions are “file exists ⇒ executed”, “fixed JSON ⇒ live health”, “device opens ⇒ ioctl verified” and “schema parses ⇒ behavior passed”. Independent adversarial controls exposed these despite all focused tests passing. Returning unknown and preserving failed evidence costs less than repeatedly correcting unsupported green status.

## 7. Verification Matrix

| Scope | Observed result | Limit |
|---|---|---|
| Physical host checks | 3 hello + 2 time + 3 expected SSP aborts | Eight invocations at recorded times; not persistent service health or full isolation certification |
| Artifact identity | Initial five guest ELFs/four launch executables unchanged before/after; SSP staged/build digests equal and unchanged | No independent rebuild or quiesced pristine source snapshot |
| Dune Mirage | 5 targets passed; 6 runner selfchecks included | Host-library/probe checks; weak negative coverage |
| Gleam Mirage | 24/24 on OTP 29.0.6 | Existing focused tests, not full CEPAF suite |
| Web / tools | 12/12 web, 14/14 tools | No new tender negative acceptance cases in these suites |
| Isolated negative controls | Empty files pass gate; fake executable/empty guest pass; path injection flips failure; slow process requires external timeout; unavailable-tender test passes; virtio exit 83 survives missing success and explicit abort | Defects reproduced, not passing production behavior |
| Live links | HTTP 200 for [cockpit](http://nas-1.tail55d152.ts.net:4100/mirage), [hypervisors](http://nas-1.tail55d152.ts.net:4100/api/v1/mirage/hypervisors), [status](http://nas-1.tail55d152.ts.net:4100/api/v1/mirage/status), [candidates](http://nas-1.tail55d152.ts.net:4100/api/v1/mirage/candidates), [benchmark contract](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-1037-mirage-benchmark-contract.md) | HTTP reachability does not prove semantic accuracy |
| MIG-01..MIG-07 | Seven mapped, NOT_VERIFIED; verified_admitted_count=0 | measured_ram_savings_mb is null/unknown, not a measured zero; 1092 MB is projected |
| Runtime status | simulation_only; health/observation unknown | Consistent with no connected supervised application observation |
| Full CEPAF regression | Not rerun | Submitted aggregate count not independently confirmed |
| Candidate formal gates | Not run; no candidate-specific formal receipt validated | No two-key admission, SIL certification or all-aspect proof |

The original 17 aspect IDs are preserved in the machine evidence, each with full runtime/formal admission UNRUN. Scoped observations bear on A01 hardware, A02 JJ, A03 purity, A04 OTP, A06 evidence, A08 separation, A12/A13 projections, A14 links, A15 checklist and A16 knowledge. They do not establish the complete obligations; A05/A07/A09/A10/A11/A17 also receive no new admission credit.

<details>
<summary>Five-domain, 18-checkpoint review checklist — scoped evidence, not 18/18 production admission</summary>

**Domain 1 — Metadata / time / navigation**

- [x] CHK-01-TIME — Host UTC/chrony sample and per-run UTC intervals recorded; fleet and Lamport synchronization not proved.
- [x] CHK-02-TAIL — Five relevant live FQDN links checked; new document publishing pending integration.
- [x] CHK-03-FRACT — Fractal and knowledge tags included.
- [x] CHK-04-KM — Governing 17-aspect design, reviewed journal and machine evidence linked.

**Domain 2 — Purity / storage**

- [x] CHK-05-MUDA — No binary or external source imported by this review; scoped dependency manifests contain neither barred engine.
- [x] CHK-06-GRAPH — No graph/native control implementation added.
- [ ] CHK-07-DRIVE — No drive mutations performed; actual storage-interlock gate not exercised.

**Domain 3 — Test / mathematical evidence**

- [ ] CHK-08-C1C8 — Focused tests pass but negative controls identify defects; complete modalities unverified.
- [ ] CHK-09-MATH — No new Lean/Gospel/Quint proof; physical measurements are not a formal admission theorem.
- [ ] CHK-10-9MOD — Full nine-modality matrix not executed.
- [ ] CHK-11-REGR — Full CEPAF suite not rerun; narrow suites recorded above.

**Domain 4 — Runtime / observability**

- [ ] CHK-12-GLEAM — Isolated OTP 29 tests pass; live service observed on OTP 27 and supervised tender observer absent.
- [ ] CHK-13-HERMES — Dune checks pass; receipt and bounded-execution defects prevent admission.
- [ ] CHK-14-ZIGVM — External OPAM toolchain used read-only; no ZigVM kernel/VFS proof rerun.
- [ ] CHK-15-MAX — No inference exercised.
- [ ] CHK-16-OTEL — Local traces and coordinator references recorded; collector/backend correlation not established.

**Domain 5 — Governance / VCS**

- [x] CHK-17-SOV — Independent Astra review and actual AGY acknowledgement recorded; no unanimous approval or admission claimed.
- [x] CHK-18-JJ — Standalone JJ; frozen candidate; isolated review documentation; no native Git commands or main move.

</details>

## 8. Files Modified

Only this journal and [the machine evidence JSON](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1256-mirage-solo5-review-evidence.json) were added by the review. No product source file changed. Raw logs, bounded-trace output, empty fixtures and tool caches remain unversioned under the review workspace's `var/review/`; the JSON embeds the decisive bounded outputs and digests.

The independent OCaml reproducer is retained at `/tmp/uos-mirage-receipt-review.WlcKg2/receipt_review.ml`. It compiled the exact candidate probe (SHA-256 `afb1b1a8af93a17d38cd73f2f790b7351c3ecf2ffa990aab0f461580e4106088`) with trusted local true/false/sleep fixtures. Its generated binaries did not enter JJ. For durable reproduction, the evidence JSON embeds the harness source, compiler arguments, eight empty gate paths and precise fixture instructions.

## 9. Architectural Observations

The best next feature is **MIRAGE-REC-01: a bounded tender conformance and receipt service**, with Gleam/OTP owning workers, authorization, leases, deadlines and event projection; Hermes OCaml owning typed receipt validation and independent outcome oracles. Its acceptance contract must reject missing/stale/forged/partial observations, wrong candidate or artifacts, unsafe paths, process failures and output truncation. The same validated state must feed CLI, REST, cockpit and TUI.

After that, **MIG-08-METRICS** can measure per-target startup-to-readiness distributions, CPU/RSS and failure counts, including sample count and measurement scope. A small real Mirage/OCaml metrics exporter is a useful first application candidate once it has an actual target build, boot, network, restart and formal-conformance record. Do not substitute configured RAM projections or a single hello launch time for service benchmarks.

No generic shell, SQLite host database, solver subprocess or OTP supervisor is implicitly migrated by these Solo5 tests.

## 10. Remaining Gaps

MR-01..MR-09 remain open at b64532f3. AGY explicitly agreed to preserve that candidate and prepare repairs in a separate revision. The follow-up needs per-test output predicates, all-target aggregation, absence/staleness/adversarial tests, real observed projections, bounded process cleanup and truthful OTP version reporting.

Source locator is `/home/an/dev/ver/zigvm/_opam/.opam-switch/sources/solo5.0.12.1/`. The installed OPAM record declares a Solo5 0.12.1 release checksum; neither that entire snapshot nor a clean rebuild was independently verified. External writers were not quiesced. Those limits remain even though the staged SSP binaries matched the supplied build outputs.

The three execution targets do not establish every Solo5 target/hypervisor, network/storage isolation properties, Mirage application service behavior, primary/backup continuity, or production SLOs.

## 11. Metrics Summary

Observed counts: **8 physical target-specific tests**, **24 focused Mirage tests**, **5 Dune targets** (including **6** runner selfchecks), **12 web tests**, **14 tools tests**, **5 live HTTP links**, and **7 negative controls** (gate and selfcheck share one empty-fixture control). No service migration was admitted; measured RAM savings remains unknown.

One independent Astra/max reviewer ran alongside local deterministic checks. No OpenRouter request was made. Token and monetary cost were not measured. Shared service restarts, main moves, production source edits and external source imports by this reviewer: **0**.

## 12. STAMP & Constitutional Alignment

This review keeps observation separate from authorization. It refuses to turn successful host tests, test-suite labels, an ACK, or a configured boolean into system admission. No native Git operation, destructive storage action, shared journal regeneration or Zenoh key deletion occurred.

Actual AGY response `op-agy-send-codex-provenance-144600` acknowledges the two blocking reports (coordinator ACK sequences 234 and 235), agrees with the defects and preserves the candidate. Findings were sent to both AGY and Claude; SSP results were subsequently sent as `codex-mirage-ssp-findings-20260907-1248`. These are peer review records, not signatures granting deployment.

Reviewable decision summary: retain successful empirical results, request changes to the implementation, and let AGY repair a separate revision. Alternatives considered were blanket approval from the passing suites, or discarding all host-test evidence; neither fits the observed positive and negative controls. Conditional forecast: rerunning the same negative fixtures against this frozen candidate will retain the documented false positives. A repaired candidate should reject them; no numeric confidence, completion date or consciousness score is invented.

## 13. Conclusion

The requested independent review is complete for the frozen candidate. HVT, SPT and QEMU/KVM virtio executed the named test artifacts; the additional timing and SSP observations are recorded. **The verification implementation and continuing “verified” claims require changes.** All seven application candidates remain unverified, and there is no production approval. AGY has acknowledged the findings and owns the separate repair revision.
