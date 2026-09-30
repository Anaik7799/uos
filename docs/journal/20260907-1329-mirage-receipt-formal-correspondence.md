# 20260907-1329 — Mirage receipt admission model and implementation correspondence

#fractal-l0 #fractal-l3 #fractal-l4 #zk-adr #zero-muda #tailscale-web

**UOS / Mirage / Independent verification** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)

**Live document:** [Rendered](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1329-mirage-receipt-formal-correspondence.md) · [Raw source](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1329-mirage-receipt-formal-correspondence.md). These are canonical navigation locations; this isolated lane did not publish or check serving of its new files.

## 1. Scope & Trigger

Task `uos/mirage-security/20260907-1310`, lane `MIRAGE-VERIFY`, requested independent verification of the Solo5 repair. The parent coordinates Sa-plan and integration. This lane produced a pure executable receipt-admission specification and checked its formal obligations. **The Mirage implementation is not approved or admitted by these results.**

Implementation correspondence is bound to `2ce5e7b51daf6f3e834a8907a9e3f58688c20819`. Previously executed adversarial controls remain bound to `a1e700517dbff56f05a88baad9ebce89c1d6f4a2`; they were not relabeled as observations of the newer revision. The parent redirected this lane to pure formal work before any v2 control execution.

## 2. Pre-State Assessment

The initial review found that observed exit status, claimed receipt labels, and artifact presence did not establish guest behavior or evidence identity. On `a1e70051`, independent executions reproduced accepted empty guests, shell-path injection, accepted incomplete output, malformed gate input, and stale receipt projection. The [preserved adversarial evidence](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1304-mirage-independent-adversarial-evidence.json) contains the exact outputs and candidate identifier.

The newer revision contains real source changes for argv invocation, an ioctl probe, and three-target aggregation. It still lacks the structured fields required by this reference model. A passing reference model therefore cannot be substituted for implementation evidence.

## 3. Execution Detail

The formal-technique-selection skill was applied to two subjects: the conjunction of typed receipt predicates, and delayed observation transitions across context changes. [Lean source](http://nas-1.tail55d152.ts.net:4100/files/formal/lean/MirageReceiptAdmission.lean) provides an executable specification with 13 named theorems and 25 concrete examples. [Quint source](http://nas-1.tail55d152.ts.net:4100/files/formal/quint/mirage_receipt_admission.qnt) covers bounded interleavings. Neither introduces a runtime policy adapter.

The semantic carrier is an expected context plus optional HVT, SPT, and virtio receipts and a separate formal receipt. Runtime bindings include exact candidate, host, boot, invocation, source provenance, guest digest, and tender digest. A valid runtime receipt additionally requires an explicit profile, ordered observation times, a positive freshness limit, a duration bound, complete nonempty bounded output, an output digest, authentic observation, and a reaped process group. The formal receipt independently binds the candidate, expected specification digest, toolchain digest, proof digest, checked outcome, and freshness.

The `hello` profile requires the target-specific host status together with guest exit zero, a success marker, and absence of abort. The `expectedSspAbort` profile requires the expected host status and abort evidence while rejecting normal-success evidence. HVT/SPT normal status is 0; virtio is 83. The expected SSP host statuses are 255/255/83. These status values alone never establish a successful guest. The three-target admission function requires the normal profile for every target, so an expected abort does not become application readiness.

`record`, `replaceContext`, `tick`, and `recordFormal` invalidate cached admission. `admit` recomputes the complete conjunction. `trace_preserves` proves the invariant for arbitrary finite sequences of those model events from a state satisfying the invariant. The model does not prove that the concrete system implements those events.

The [independent OCaml oracle](http://nas-1.tail55d152.ts.net:4100/files/tools/verification/mirage/admission_reference_check.ml) reads the executable Lean decision table and computes explicit rejection reasons using an independently written exit/profile lookup table. It checks the exact finite Cartesian universe and rejects duplicate, out-of-universe, or missing cases. This checks the specification's executable decisions; it does not reimplement the product probe and call that product testing.

## 4. Root Cause Analysis

The evidence boundary needs a total validation function before readiness can be projected. Decoding arbitrary claimed booleans, checking substrings, or truncating observation output loses the relationship between a claim and the execution it describes. A current timestamp on an outer report does not establish freshness of its inner executions.

The model names each required fact separately so that an implementation gap is visible. Authenticity, clock reliability, and cleanup are external obligations; representing them as fields does not prove that they occurred. The expected context must come from a trusted, revision-bound authority rather than from the receipt being checked.

## 5. Fix Taxonomy

This change adds specification, tests, and evidence only. No production function was repaired by this lane. The component packet is: typed receipt carrier; current-context denotation; record/revalidate operations; readiness observation; binding, freshness, completeness, and profile laws; independent deficit oracle; finite generators; positive witnesses; and two distinct transition mutants.

The modeled acceptance laws are `valid_binds_candidate`, `valid_binds_boot`, `valid_is_fresh`, `wrong_candidate_rejected`, `missing_virtio_rejected`, `missing_formal_rejected`, and `trace_preserves`. The first mutant keeps admission after freshness expiry. The second retains admission after removing virtio. They violate freshness and target completeness respectively.

## 6. Patterns & Anti-Patterns Discovered

Separate successful-test conformance from deployment authority and from expected-failure conformance. Expected SSP termination is useful evidence, but its virtio status overlaps the normal status. Do not allow that overlap to erase the profile distinction.

Keep a reachable successful witness alongside negative controls. The normal Quint random runs did not reach an admitted witness; this is reported rather than hidden. A deterministic lifecycle test reaches admission through all six launch/completion events. A second simulation begins with independently specified valid receipts to exercise subsequent invalidation.

## 7. Verification Matrix

| Check | Observed result | Scope |
|---|---|---|
| Lean 4.33.0 type checking and execution | Exit 0; 13 theorems and 25 examples | Reference definitions, including arbitrary finite event traces |
| Independent OCaml 5.5.0 oracle | 31,104 unique cases; 18 accepted, 31,086 rejected; zero disagreement | Complete declared finite input product; other fields held at documented fixture values |
| Quint 0.32.0 typecheck | Exit 0 | Temporal reference syntax/types |
| Quint deterministic lifecycle tests | 7/7 passed | Valid lifecycle, delayed candidate/boot/run, stale observation, missing target, failed target |
| Quint normal initialization | 1,000 seeded traces, at most 25 transitions; no invariant violation; zero tool-reported admitted witnesses | Bounded sampling, not exhaustive exploration |
| Quint valid initialization | 1,000 seeded traces, at most 25 transitions; no invariant violation; 517 tool-reported admitted witnesses | Bounded sampling after a valid receipt set |
| Sticky-freshness mutant | Exit 1, two-state counterexample | Admitted at clock 0 remains admitted at clock 2 while maximum age is 1 |
| Omitted-virtio mutant | Exit 1, two-state counterexample | Virtio removed while admission remains true |
| Runtime implementation refinement | Not established | Parent owns further candidate execution and integration |

The [formal evidence JSON](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1329-mirage-receipt-formal-evidence.json) binds source hashes, tool identity, command arguments, seeds, limits, outcomes, and counterexamples. All formal invocations had a 30-second outer deadline and two-second termination grace, except the successful Quint typecheck with a 20-second deadline. Printed Lean axiom reports name the standard `propext` axiom for the four inspected theorems; no zero-axiom claim is made, and no `sorry` or project-defined axiom was used.

### Invariant-to-code correspondence at 2ce5e7b5

| Model obligation | Candidate source location | Correspondence result |
|---|---|---|
| Exact candidate/host/boot/run/provenance/guest/tender binding | `mirage_hypervisor_probe.ml:16`, `:134`, `:150` | Receipt carries paths, exit status, snippet, and a boolean. Basename and size checks do not implement digest/context equality. Required receipt fields are absent. |
| Runtime and formal freshness | `mirage_hypervisor_probe.ml:225`; `mirage_hypervisor.gleam:282` | Outer timestamp exists. Disk projection accepts decoded reports without a freshness or current-context admission function. Separate formal receipt absent. |
| Complete bounded output and process-group cleanup facts | `mirage_hypervisor_probe.ml:176`, `:188` | Initial `select` timeout is followed by blocking line reads and `waitpid`; captured lines are truncated. No receipt fields attest output completeness or group cleanup. Pure model predicates do not certify these operations. |
| Explicit per-test outcome profile | `mirage_hypervisor_probe.ml:138`, `:142` | Predicate accepts either an exit banner or substring `SUCCESS`, rejects observed `ABORT`, and has no typed SSP profile. This differs from the model conjunction. |
| Mandatory HVT, SPT, virtio conjunction | `mirage_hypervisor_probe.ml:232` | New source includes all three receipts. This is a source-level correspondence improvement; independent runtime evidence is owned by the parent. |
| Same validated state at CLI and projection | `tools/uos/src/main.gleam:380`, `:1768`; `mirage_hypervisor.gleam:227`, `:282` | CLI still uses file sizes/substrings. Projection still decodes receipt claims. No common implementation of `ready` was found. |
| Invalidation on observation/context/formal changes | `mirage_hypervisor.gleam:282` | No event-store transition matching the reference invalidation operations is present in this reader. |

Source links: [Hermes probe](http://nas-1.tail55d152.ts.net:4100/files/engines/hermes/modules/hermes_mirage/mirage_hypervisor_probe.ml), [Gleam projection](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/services/mirage_hypervisor.gleam), [CLI gate](http://nas-1.tail55d152.ts.net:4100/files/tools/uos/src/main.gleam). The evidence JSON records hashes at the stated immutable candidate; a later live file is not that receipt.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] CHK-01-TIME — Host UTC `2026-09-07T13:34:29Z`; synchronization check reported `NTPSynchronized=yes`. Model clock is symbolic and separate.
- [x] CHK-02-TAIL — Full canonical FQDN navigation provided; serving of new isolated artifacts remains untested.
- [x] CHK-03-FRACT — Fractal and governance tags assigned.
- [x] CHK-04-KM — Journal, model, oracle, candidate source, and evidence cross-linked; no wiki ingestion claimed.

</details>
<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] CHK-05-MUDA — This lane adds no banned source, dependency, or runtime role.
- [x] CHK-06-GRAPH — Model and oracle use pure Lean/OCaml data and Quint transitions; no graph NIF added.
- [ ] CHK-07-DRIVE — Storage interlock execution outside this lane.

</details>
<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI protocol not executed by this model lane.
- [ ] CHK-09-MATH — Global four-metric gates not measured; scoped theorems and finite checks reported above.
- [ ] CHK-10-9MOD — No nine-modality system-wide result claimed.
- [ ] CHK-11-REGR — No new live service regression or monitoring run after the parent narrowed scope.

</details>
<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Earlier candidate compiled on OTP 29; live supervision/cutover belongs to the parent.
- [ ] CHK-13-HERMES — Pure reference checks passed; authoritative store/refinement and actual process guarantees remain open.
- [ ] CHK-14-ZIGVM — External OPAM compiler used read-only; no ZigVM execution-kernel proof rerun.
- [ ] CHK-15-MAX — Inference outside scope.
- [ ] CHK-16-OTEL — Collector and trace propagation outside scope.

</details>
<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] CHK-17-SOV — No candidate approval, system admission, or deployment authority issued.
- [x] CHK-18-JJ — Isolated JJ workspace; only owned artifacts added; no native Git or main-bookmark mutation.

</details>

## 8. Files Modified

Added the Lean model, Quint model, OCaml reference checker, this journal, formal evidence JSON, and preserved earlier adversarial evidence. The earlier reproducible controls are `tools/verification/mirage/{probe_adversarial,probe_fixture,gate_fixture}.ml` and `projection_control.erl`. Their outputs are bound only to `a1e70051`.

Two additional source fixtures, `probe_v2_adversarial.ml` and `probe_v2_fixture.ml`, were prepared before the scope change and remain **UNRUN**. Model CSV, counterexample traces, compiler products, and local fixture directories remain ignored under `var/mirage-verification/`. The formal JSON embeds compact mutant traces and all decisive verification results for durable review.

## 9. Architectural Observations

The model is an executable specification and independent oracle, not extracted production code. Production correspondence requires one typed validator and a supervised producer that supplies the exact bound facts. CLI/API/UI should project the validator's verdict, with missing, stale, incomplete, or malformed evidence represented explicitly.

Opaque natural-number digests preserve equality structure only. They prove no hashing, signatures, ELF identity, source pinning, run uniqueness, reliable monotonic clock, storage atomicity, or authentic host behavior. There is no extraction freshness guarantee linking this Lean program to the OCaml/Gleam binaries.

## 10. Remaining Gaps

Implementation/model refinement remains open for the obligations in the correspondence table. The parent owns further runtime tests, Sa-plan status, peer coordination, and any integration. The finite oracle exhausts only its declared 31,104-case universe. Quint random simulation proves neither exhaustive state safety nor liveness. Its identities are finite abstractions, and expected-context authenticity and uniqueness are assumptions outside the model.

No full 17-aspect, migration, application benchmark, network/storage isolation, high-availability, or production SLO claim follows from these artifacts.

## 11. Metrics Summary

Observed pure results: 13 named Lean theorems, 25 examples, 31,104 finite oracle cases, seven Quint lifecycle tests, 2,000 sampled traces bounded at 25 transitions each, and two detected mutant counterexamples. The executable table contains 18 accepted and 31,086 rejected cases. No token cost or system-wide coverage metric was measured.

Production source edits, service restarts, deployments, main moves, and external source imports by this lane: zero. Only owned isolated artifacts were frozen.

## 12. STAMP & Constitutional Alignment

The unsafe control action is granting current execution credit from unbound or stale observations. The constraint is conjunction over complete current-context evidence, followed by invalidation when that evidence's context changes. Formal results advise and can veto; they do not directly execute side effects or grant deployment permission.

The formal check and adversarial review remain distinguishable evidence keys. Peer messages and a passing proof cannot close Sa-plan or waive runtime checks. The parent's narrowing instruction ended further security reproductions in this lane, while preserving the earlier observed evidence and unrun source fixtures without reclassification.

## 13. Conclusion

The reference-model packet is complete and machine checked within its stated scope. It provides executable admission predicates, finite oracle agreement, transition invariants, positive witnesses, and live mutant counterexamples. **The Mirage candidate remains unapproved; implementation correspondence and runtime acceptance are separate outstanding work.**

**Previous:** [Independent tender review](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1256-mirage-solo5-independent-review.md) · **Next:** [Formal evidence](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1329-mirage-receipt-formal-evidence.json)

**UOS footer:** Independent model evidence; no deployment or system admission authority.
